defmodule Ecspanse.Server do
  @moduledoc """
  The Server is responsible for managing the internal state of the framework, scheduling and running the Systems and batching the Events.

  """
  require Ex2ms
  require Logger

  alias Ecspanse.Frame
  alias Ecspanse.System
  alias Ecspanse.Util

  @doc """
  TODO
  Utility function used for testing and development purposes.

  The `debug/0` function returns the internal state of the framework, which can be useful for debugging systems scheduling and batching.
  This function is only available in the `:dev` and `:test` environments.

  ## Returns

  The internal state of the framework.

  > #### This function is intended for use only in testing and development environments.  {: .warning}
  """
  @spec debug() :: Ecspanse.Server.State.t()
  def debug do
    GenServer.call(__MODULE__, :debug)
  end

  @doc """
  TODO
  WARNING: to be used only for development and testing.

  Utility function for testing and development purposes.
  The server is turned to test mode.
  A `{:next_frame, %Ecspanse.Server.State{}}` tupple message will be sent to the process running this function at the beginning of each frame.
  This is useful for tests or debugging
  """
  def test_server(test_pid) do
    GenServer.cast(__MODULE__, {:test_server, test_pid})
  end

  #############################
  #    INTERNAL STATE         #
  #############################

  defmodule State do
    @moduledoc """
    The internal state of the framework.
    """

    @type t :: %__MODULE__{
            status:
              :startup_systems
              | :frame_start_systems
              | :batch_systems
              | :frame_end_systems
              | :frame_ended,
            frame_timer: :running | :finished,
            ecspanse_module: module(),
            system_run_conditions_map: map(),
            startup_systems: list(Ecspanse.System.t()),
            frame_start_systems: list(Ecspanse.System.t()),
            batch_systems: list(list(Ecspanse.System.t())),
            frame_end_systems: list(Ecspanse.System.t()),
            shutdown_systems: list(Ecspanse.System.t()),
            scheduled_systems: list(Ecspanse.System.t()),
            await_systems: list(reference()),
            system_modules: MapSet.t(module()),
            last_frame_monotonic_time: integer(),
            fps_limit: non_neg_integer(),
            delta: non_neg_integer(),
            frame_data: Frame.t(),
            test: boolean(),
            test_pid: pid() | nil
          }

    @enforce_keys [
      :ecspanse_module,
      :last_frame_monotonic_time,
      :fps_limit,
      :delta
    ]

    defstruct status: :startup_systems,
              frame_timer: :running,
              ecspanse_module: nil,
              system_run_conditions_map: %{},
              startup_systems: [],
              frame_start_systems: [],
              batch_systems: [],
              frame_end_systems: [],
              shutdown_systems: [],
              scheduled_systems: [],
              await_systems: [],
              system_modules: MapSet.new(),
              last_frame_monotonic_time: nil,
              fps_limit: :unlimited,
              delta: 0,
              frame_data: %Frame{},
              test: false,
              test_pid: nil
  end

  ### SERVER ###

  use GenServer

  @doc false
  def start_link(payload) do
    GenServer.start_link(__MODULE__, payload, name: __MODULE__)
  end

  @impl true
  def init(payload) do
    # The main reason for using ETS tables are:
    # - keep under control the GenServer memory usage
    # - elimitate GenServer bottlenecks. Various Systems or Queries can read directly from the ETS tables.

    # This is the main ETS table that holds the components state
    # as a list of `{{Ecspanse.Entity.id(), component_module :: module()}, tags :: list(atom()),component_state :: struct()}`
    # All processes can read and write to this table. But writing should only be done through Commands.
    # The race condition is handled by the System Component locking.
    # Commands should validate that only Systems are writing to this table.
    components_state_ets_table =
      :ets.new(:ets_ecspanse_components_state, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: :auto
      ])

    # This is the ETS table that holds the resources state as a list of `{resource_module :: module(), resource_state :: struct()}`
    # All processes can read and write to this table.
    # But writing should only be done through Commands.
    # Commands should validate that only Systems are writing to this table.
    resources_state_ets_table =
      :ets.new(:ets_ecspanse_resources_state, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: false
      ])

    # This ETS table stores Events as a list of event structs wraped in a tuple {{MyEventModule, key :: any()}, %MyEvent{}}.
    # Every frame, the objects in this table are deleted.
    # Any process can read and write to this table.
    # But the logic responsible to write to this table should check the stored values are actually event structs.
    # Before being sent to the Systems, the events are sorted by their inserted_at timestamp, and group in batches.
    # The batches are determined by the unicity of the event {EventModule, key} per batch.

    events_ets_table =
      :ets.new(:ets_ecspanse_events, [
        :duplicate_bag,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    # Store the ETS tables in an Agent so they can be accessed independently from this GenServer
    Agent.start_link(
      fn ->
        %{
          components_state_ets_table: components_state_ets_table,
          resources_state_ets_table: resources_state_ets_table,
          events_ets_table: events_ets_table
        }
      end,
      name: :ecspanse_ets_tables
    )

    state = %State{
      ecspanse_module: payload.ecspanse_module,
      last_frame_monotonic_time: Elixir.System.monotonic_time(:millisecond),
      delta: 0,
      fps_limit: payload.fps_limit
    }

    # Special system that creates the default resources
    create_default_resources_system =
      %System{
        module: Ecspanse.System.CreateDefaultResources,
        queue: :startup_systems,
        execution: :sync,
        run_conditions: []
      }

    %Ecspanse.Data{operations: operations} = state.ecspanse_module.setup(%Ecspanse.Data{})
    operations = operations ++ [{:add_system, create_default_resources_system}]

    state = operations |> Enum.reverse() |> apply_operations(state)

    send(self(), :run)

    {:ok, state}
  end

  @impl true
  def handle_call(:debug, _from, state) do
    {:reply, state, state}
  end

  @impl true
  # WARNING: to be used only for development and testing.
  def handle_cast({:test_server, test_pid}, state) do
    state = %{
      state
      | test: true,
        test_pid: test_pid
    }

    {:noreply, state}
  end

  @impl true
  def handle_info(:run, state) do
    # there are no events during startup
    event_batches = []

    state = %{
      state
      | scheduled_systems: state.startup_systems,
        frame_data: %Frame{event_batches: event_batches}
    }

    :ets.delete_all_objects(Util.events_ets_table())

    send(self(), :run_next_system)
    {:noreply, state}
  end

  def handle_info(:start_frame, state) do
    # use monotonic time
    # https://til.hashrocket.com/posts/k6kydebcau-precise-timings-with-monotonictime
    frame_monotonic_time = Elixir.System.monotonic_time(:millisecond)
    delta = frame_monotonic_time - state.last_frame_monotonic_time

    event_batches =
      Util.events_ets_table()
      |> :ets.tab2list()
      |> batch_events()

    # Frame limit
    # in order to finish a frame, two conditions must be met:
    # 1. the frame time must pass: eg 1000/60 milliseconds.
    # .  this sets the frame_timer: from :running to :finished
    # 2. all the frame systems must have finished running
    # .  this sets the status: to :frame_ended,
    # So, when state.frame_timer == :finished && state.status == :frame_ended, the frame is finished

    one_sec = 1000
    limit = if state.fps_limit == :unlimited, do: 0, else: one_sec / state.fps_limit

    # the systems run conditions are refreshed every frame
    # this is intentional behaviour for performance reasons
    # but also to avoid inconsistencies in the components
    state = refresh_system_run_conditions_map(state)

    state = %{
      state
      | status: :frame_start_systems,
        frame_timer: :running,
        scheduled_systems: state.frame_start_systems,
        last_frame_monotonic_time: frame_monotonic_time,
        delta: delta,
        frame_data: %Frame{
          delta: delta,
          event_batches: event_batches
        }
    }

    # Delete all events from the ETS table
    :ets.delete_all_objects(Util.events_ets_table())

    Process.send_after(self(), :finish_frame_timer, round(limit))
    send(self(), :run_next_system)

    # if the test_server/1 function is called, send the state to the test process
    if state.test do
      send(state.test_pid, {:next_frame, state})
    end

    {:noreply, state}
  end

  # finished running strartup systems (sync) and starting the loop
  def handle_info(
        :run_next_system,
        %State{scheduled_systems: [], status: :startup_systems} = state
      ) do
    send(self(), :start_frame)
    {:noreply, state}
  end

  # finished running systems at the beginning of the frame (sync) and scheduling the batch systems
  def handle_info(
        :run_next_system,
        %State{scheduled_systems: [], status: :frame_start_systems} = state
      ) do
    state = %{state | status: :batch_systems, scheduled_systems: state.batch_systems}

    send(self(), :run_next_system)
    {:noreply, state}
  end

  # finished running batch systems (async per batch) and scheduling the end of the frame systems
  def handle_info(:run_next_system, %State{scheduled_systems: [], status: :batch_systems} = state) do
    state = %{state | status: :frame_end_systems, scheduled_systems: state.frame_end_systems}

    send(self(), :run_next_system)
    {:noreply, state}
  end

  # finished running systems at the end of the frame (sync) and scheduling the end of frame
  def handle_info(
        :run_next_system,
        %State{scheduled_systems: [], status: :frame_end_systems} = state
      ) do
    send(self(), :end_frame)
    {:noreply, state}
  end

  # running batch (async) systems. This runs only for `batch_systems` status
  def handle_info(
        :run_next_system,
        %State{scheduled_systems: [systems_batch | batches], status: :batch_systems} = state
      ) do
    systems_batch = Enum.filter(systems_batch, &run_system?(&1, state.system_run_conditions_map))

    case systems_batch do
      [] ->
        state = %{state | scheduled_systems: batches, await_systems: []}
        send(self(), :run_next_system)
        {:noreply, state}

      systems_batch ->
        # Choosing this approach instead of using `Task.async_stream` because
        # we don't want to block the server while processing the batch
        # Also it re-uses the same code as the sync systems
        refs = Enum.map(systems_batch, &run_system(&1, state))

        state = %{state | scheduled_systems: batches, await_systems: refs}

        {:noreply, state}
    end
  end

  # running sync systems
  def handle_info(:run_next_system, %State{scheduled_systems: [system | systems]} = state) do
    if run_system?(system, state.system_run_conditions_map) do
      ref = run_system(system, state)
      state = %{state | scheduled_systems: systems, await_systems: [ref]}

      {:noreply, state}
    else
      state = %{state | scheduled_systems: systems, await_systems: []}
      send(self(), :run_next_system)
      {:noreply, state}
    end
  end

  # systems finished running and triggering next. The message is sent by the Task
  def handle_info({ref, :finished_system_execution}, %State{await_systems: [ref]} = state)
      when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    state = %State{state | await_systems: []}

    send(self(), :run_next_system)
    {:noreply, state}
  end

  def handle_info(
        {ref, :finished_system_execution},
        %State{await_systems: system_refs} = state
      )
      when is_reference(ref) do
    unless ref in system_refs do
      raise "Received System message from unexpected System: #{inspect(ref)}"
    end

    Process.demonitor(ref, [:flush])
    state = %State{state | await_systems: List.delete(system_refs, ref)}
    {:noreply, state}
  end

  # finishing the frame systems and scheduling the next one
  def handle_info(:end_frame, state) do
    state = %State{state | status: :frame_ended}

    if state.frame_timer == :finished do
      send(self(), :start_frame)
    end

    {:noreply, state}
  end

  def handle_info(:finish_frame_timer, state) do
    state = %State{state | frame_timer: :finished}

    if state.status == :frame_ended do
      send(self(), :start_frame)
    end

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Running shutdown_systems. Those cannot run in the standard way because the process is shutting down.
    # They are executed sync, in the ordered they were added.
    Enum.each(state.shutdown_systems, fn system ->
      task =
        Task.async(fn ->
          prepare_system_process(system)
          system.module.run(state.frame_data)
        end)

      Task.await(task)
    end)
  end

  ### HELPER ###

  defp run_system(system, state) do
    %Task{ref: ref} =
      Task.async(fn ->
        prepare_system_process(system)
        system.module.schedule_run(state.frame_data)
        :finished_system_execution
      end)

    ref
  end

  # This happens in the System process
  defp prepare_system_process(system) do
    Process.put(:ecs_process_type, :system)
    Process.put(:system_execution, system.execution)
    Process.put(:system_module, system.module)
    Process.put(:locked_components, system.module.__locked_components__())
  end

  defp apply_operations([], state), do: state

  defp apply_operations([operation | operations], state) do
    %State{} = state = apply_operation(operation, state)
    apply_operations(operations, state)
  end

  # batch async systems
  defp apply_operation(
         {:add_system,
          %System{queue: :batch_systems, module: system_module, run_after: []} = system},
         state
       ) do
    state = validate_unique_system(system_module, state)

    batch_systems = Map.get(state, :batch_systems)

    # should return a list of lists
    new_batch_systems = batch_system(system, batch_systems, [])

    Map.put(state, :batch_systems, new_batch_systems)
    |> Map.put(
      :system_run_conditions_map,
      add_to_system_run_conditions_map(state.system_run_conditions_map, system)
    )
  end

  defp apply_operation(
         {:add_system,
          %System{queue: :batch_systems, module: system_module, run_after: after_systems} = system},
         state
       ) do
    state = validate_unique_system(system_module, state)
    batch_systems = Map.get(state, :batch_systems)

    system_modules = batch_systems |> List.flatten() |> Enum.map(& &1.module)

    non_exising_systems = after_systems -- system_modules

    if length(non_exising_systems) > 0 do
      raise "Systems #{inspect(non_exising_systems)} does not exist. A system can run only after existing systems"
    end

    # should return a list of lists
    new_batch_systems = batch_system_after(system, after_systems, batch_systems, [])

    Map.put(state, :batch_systems, new_batch_systems)
    |> Map.put(
      :system_run_conditions_map,
      add_to_system_run_conditions_map(state.system_run_conditions_map, system)
    )
  end

  # add sequential systems to their queues
  defp apply_operation(
         {:add_system, %System{queue: queue, module: system_module} = system},
         state
       ) do
    state = validate_unique_system(system_module, state)

    Map.put(state, queue, Map.get(state, queue) ++ [system])
    |> Map.put(
      :system_run_conditions_map,
      add_to_system_run_conditions_map(state.system_run_conditions_map, system)
    )
  end

  defp validate_unique_system(system_module, state) do
    Ecspanse.Util.validate_ecs_type(
      system_module,
      :system,
      ArgumentError,
      "The module #{inspect(system_module)} must be a System"
    )

    if MapSet.member?(state.system_modules, system_module) do
      raise "System #{inspect(system_module)} already exists. Server systems must be unique."
    end

    %State{state | system_modules: MapSet.put(state.system_modules, system_module)}
  end

  defp batch_system(system, [], []) do
    [[system]]
  end

  defp batch_system(system, [], checked_batches) do
    checked_batches ++ [[system]]
  end

  defp batch_system(system, [batch | batches], checked_batches) do
    system_locked_components = system.module.__locked_components__()

    batch_locked_components =
      Enum.map(batch, & &1.module.__locked_components__()) |> List.flatten()

    if batch_locked_components -- system_locked_components == batch_locked_components do
      updated_batch = batch ++ [system]
      checked_batches ++ [updated_batch] ++ batches
    else
      batch_system(system, batches, checked_batches ++ [batch])
    end
  end

  defp batch_system_after(system, [] = _after_systems, remaining_batches, checked_batches) do
    batch_system(system, remaining_batches, checked_batches)
  end

  defp batch_system_after(system, after_system_modules, [batch | batches], checked_batches) do
    remaining_after_systems = after_system_modules -- Enum.map(batch, & &1.module)

    batch_system_after(
      system,
      remaining_after_systems,
      batches,
      checked_batches ++ [batch]
    )
  end

  # builds a map with all running conditions from all systems
  # this allows to run the conditions only per frame
  defp add_to_system_run_conditions_map(
         existing_conditions,
         %{run_conditions: run_conditions} = _system
       ) do
    run_conditions
    |> Enum.reduce(existing_conditions, fn condition, acc ->
      # Adding false as initial value for the condition
      # because this cannot run on startup systems
      # this will be updated in the refresh_system_run_conditions_map
      Map.put(acc, condition, false)
    end)
  end

  # takes state and returns state
  defp refresh_system_run_conditions_map(state) do
    state.system_run_conditions_map
    |> Enum.reduce(
      state,
      fn {{module, function, args} = condition, _value}, state ->
        result = apply(module, function, args)

        unless is_boolean(result) do
          raise "System run condition functions must return a boolean. Got: #{inspect(result)}. For #{inspect({module, function, args})}."
        end

        %State{
          state
          | system_run_conditions_map: Map.put(state.system_run_conditions_map, condition, result)
        }
      end
    )
  end

  defp run_system?(system, run_conditions_map) do
    Enum.all?(system.run_conditions, fn condition ->
      Map.get(run_conditions_map, condition) == true
    end)
  end

  defp batch_events(events) do
    # inserted_at is the System time in milliseconds when the event was created
    events
    |> Enum.sort_by(fn {_k, v} -> v.inserted_at end, &</2)
    |> do_event_batches([])
  end

  defp do_event_batches([], batches), do: batches

  defp do_event_batches(events, batches) do
    current_events = Enum.uniq_by(events, fn {k, _v} -> k end)

    batch =
      Enum.map(current_events, fn {_, v} -> v end)

    remaining_events = events -- current_events
    do_event_batches(remaining_events, batches ++ [batch])
  end
end
