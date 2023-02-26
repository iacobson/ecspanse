defmodule Ecspanse.World do
  @moduledoc """
  TODO

  config:
  - opt_app - optional - the otp application
  - fps_limit - optional - the number of frames per second. Defaults to  :unlimited


  # TODO:
  Tutorial on signing and verifying the token.
  - set opt_app: :my_otp_app option in the world module
  - set :my_otp_app, :ecspanse_secret in the config

  Otherwise the token is signed with a default secret.


  Special resources
  such as State, are created by default by the framework.


  Describe how conditionally running systems works.
  `run_in_state: [:state1]` `run_not_in_state: [:state2]` `run_if: [{Module, :function}]
  for `run_if` functions, the tokens is passed as argument

  """
  require Ex2ms
  require Logger

  alias __MODULE__
  alias Ecspanse.System

  @type t :: %__MODULE__{
          operations: operations(),
          system_set_options: map()
        }

  @type operation ::
          {:add_system, System.system_queue(), Ecspanse.System.t()}
          | {:add_system, :batch_systems, Ecspanse.System.t(), opts :: keyword()}
  @type operations :: list(operation())

  @type name :: atom() | {:global, term()} | {:via, module(), term()}
  @type supervisor :: pid() | atom() | {:global, term()} | {:via, module(), term()}

  defstruct operations: [], system_set_options: %{}

  @doc "TODO The setup callback receives a World.t() and returns the World.t()"
  @callback setup(t()) :: t()

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      @behaviour Ecspanse.World

      otp_app = Keyword.get(opts, :otp_app)
      fps_limit = Keyword.get(opts, :fps_limit, :unlimited)

      if otp_app && not is_atom(otp_app) do
        raise ArgumentError,
              "The key :otp_app must be an atom in World module #{inspect(__MODULE__)}"
      end

      if fps_limit && not (is_integer(fps_limit) || fps_limit == :unlimited) do
        raise ArgumentError,
              "If set, the option :fps_limit must be a non negative integer in the World module #{inspect(__MODULE__)}"
      end

      Module.register_attribute(__MODULE__, :otp_app, accumulate: false)
      Module.put_attribute(__MODULE__, :otp_app, otp_app)
      Module.register_attribute(__MODULE__, :fps_limit, accumulate: false)
      Module.put_attribute(__MODULE__, :fps_limit, fps_limit)
      Module.register_attribute(__MODULE__, :ecs_type, accumulate: false)
      Module.put_attribute(__MODULE__, :ecs_type, :world)

      @doc false
      def __otp_app__ do
        @otp_app
      end

      @doc false
      def __fps_limit__ do
        @fps_limit
      end

      @doc false
      def __ecs_type__ do
        @ecs_type
      end
    end
  end

  @doc """
  #TODO
  A way to group systems together.
  The opts are the same as for the systems, and they are applied on top of the system's options inside the set.
  The system sets can also be nested.


  The system sets function takes the world as argument and returns the world.
  Inside the function, new systems can be added using the add_system_* functions
  """
  @spec add_system_set(t(), {module, function}, opts :: keyword()) :: t()
  def add_system_set(world, {module, function}, opts \\ []) do
    # add the system set options to the world
    # the World system_set_options is a map with the key {module, function} for every system set
    world = %World{
      world
      | system_set_options: Map.put(world.system_set_options, {module, function}, opts)
    }

    world = apply(module, function, [world])

    # remove the system set options from the world
    %World{world | system_set_options: Map.delete(world.system_set_options, {module, function})}
  end

  @doc "TODO. Startup systems do not take options"
  @spec add_startup_system(t(), system_module :: module()) :: t()
  def add_startup_system(%World{operations: operations} = world, system_module) do
    system = %System{
      module: system_module,
      queue: :startup_systems,
      execution: :sync,
      run_conditions: []
    }

    %World{world | operations: [{:add_system, system} | operations]}
  end

  @doc """
  Executed sync in the order they were inserted at the beginning of each frame
  """
  @spec add_frame_start_system(t(), system_module :: module(), opts :: keyword()) :: t()
  def add_frame_start_system(%World{operations: operations} = world, system_module, opts \\ []) do
    opts = merge_system_options(opts, world.system_set_options)

    if Keyword.get(opts, :run_after) do
      Logger.warn(
        "The :run_after option is ignored by sync running systems. Those will always run in the order they were added to the world."
      )
    end

    system =
      %System{module: system_module, queue: :frame_start_systems, execution: :sync}
      |> add_run_conditions(opts)

    %World{world | operations: [{:add_system, system} | operations]}
  end

  @doc """
  Auto-batched and executed async for each frame

  Using the `run_after: SystemModule1` or `run_after: [SystemModule1, SystemModule2]`  option
  - the after System must be already set - this prevents circular dependencies
  - there is a deliberate choice to allow only `run_after` option. While a `before` option would simplify some relations, it can also introduce circular dependencies.
    Example:
    - Run System A
    - Run System B before System A
    - Run System C after System A, before System B
  """
  @spec add_system(t(), system_module :: module(), opts :: keyword()) ::
          t()
  def add_system(%World{operations: operations} = world, system_module, opts \\ []) do
    opts = merge_system_options(opts, world.system_set_options)

    after_system = Keyword.get(opts, :run_after)

    run_after =
      case after_system do
        nil -> []
        after_systems when is_list(after_systems) -> after_systems
        after_system when is_atom(after_system) -> [after_system]
      end

    system =
      %System{
        module: system_module,
        queue: :batch_systems,
        execution: :async,
        run_after: run_after
      }
      |> add_run_conditions(opts)

    %World{world | operations: [{:add_system, system} | operations]}
  end

  @doc """
  Executed sync in the order they were inserted, at the end of each frame
  """
  @spec add_frame_end_system(t(), system_module :: module(), opts :: keyword()) :: t()
  def add_frame_end_system(%World{operations: operations} = world, system_module, opts \\ []) do
    opts = merge_system_options(opts, world.system_set_options)

    if Keyword.get(opts, :run_after) do
      Logger.warn(
        "The :run_after option is ignored by sync running systems. Those will always run in the order they were added to the world."
      )
    end

    system =
      %System{module: system_module, queue: :frame_end_systems, execution: :sync}
      |> add_run_conditions(opts)

    %World{world | operations: [{:add_system, system} | operations]}
  end

  @doc """
  Run only once on World shutdown
  Does not take options
  """
  @spec add_shutdown_system(t(), system_module :: module()) :: t()
  def add_shutdown_system(%World{operations: operations} = world, system_module) do
    system = %System{
      module: system_module,
      queue: :shutdown_systems,
      execution: :sync,
      run_conditions: []
    }

    %World{world | operations: [{:add_system, system} | operations]}
  end

  @doc """
  Utility function used for developement.
  Returns the internal World state.
  Useful for debugging systems scheduling and batching.
  """
  @spec debug(token :: binary()) :: World.State.t()
  def debug(token) do
    if Mix.env() in [:dev, :test] do
      %{world_name: world_name} = Ecspanse.Util.decode_token(token)
      GenServer.call(world_name, :debug)
    else
      {:error, "debug is only available in dev and test"}
    end
  end

  #############################
  #    INTERNAL STATE         #
  #############################

  defmodule Frame do
    @moduledoc """
    A struct exposed to the systems

    - delta is the time elapsed since the last frame in milliseconds
    """

    @type t :: %__MODULE__{
            token: binary(),
            event_batches: list(list(Ecspanse.Event.t())),
            delta: non_neg_integer()
          }

    defstruct token: nil, event_batches: [], delta: 0
  end

  defmodule State do
    @moduledoc false
    # should not be present in the docs

    @opaque t :: %__MODULE__{
              token: binary(),
              id: binary(),
              status:
                :startup_systems
                | :frame_start_systems
                | :batch_systems
                | :frame_end_systems
                | :frame_ended,
              frame_timer: :running | :finished,
              world_name: Ecspanse.World.name(),
              world_pid: pid(),
              world_module: module(),
              supervisor: Ecspanse.World.supervisor(),
              components_state_ets_name: atom(),
              resources_state_ets_name: atom(),
              events_ets_name: atom(),
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
              frame_data: Frame.t()
            }

    @enforce_keys [
      :token,
      :id,
      :world_name,
      :world_pid,
      :world_module,
      :supervisor,
      :components_state_ets_name,
      :resources_state_ets_name,
      :events_ets_name,
      :last_frame_monotonic_time,
      :fps_limit,
      :delta
    ]

    defstruct token: nil,
              id: nil,
              status: :startup_systems,
              frame_timer: :running,
              world_name: nil,
              world_pid: nil,
              world_module: nil,
              supervisor: nil,
              components_state_ets_name: nil,
              resources_state_ets_name: nil,
              events_ets_name: nil,
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
              frame_data: %Frame{}
  end

  ### SERVER ###

  use GenServer

  @spec child_spec(data :: map()) :: map()
  @doc false
  def child_spec(data) do
    %{
      id: data.id,
      start: {__MODULE__, :start_link, [data]},
      restart: :transient
    }
  end

  @doc false
  def start_link(data) do
    GenServer.start_link(__MODULE__, data, name: data.world_name)
  end

  @impl true
  def init(data) do
    # The main reason for using ETS tables are:
    # - keep under control the GenServer memory usage
    # - elimitate GenServer bottlenecks. Various Systems or Queries can read directly from the ETS tables.

    # This is the main ETS table that holds the components state as a list of Ecspanse.Component.component_key_value() tuples
    # All processes can read and write to this table. But writing should only be done through Commands.
    # The race condition is handled by the System Component locking.
    # Commands should validate that only Systems are writing to this table.
    components_state_ets_name =
      :ets.new(String.to_atom("components_state:#{data.id}"), [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: :auto
      ])

    # This is the ETS table that holds the resources state as a list of Ecspanse.Resource.resource_key_value() tuples
    # All processes can read and write to this table.
    # But writing should only be done through Commands.
    # Commands should validate that only Systems are writing to this table.
    resources_state_ets_name =
      :ets.new(String.to_atom("resources_state:#{data.id}"), [
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

    events_ets_name =
      :ets.new(String.to_atom("events:#{data.id}"), [
        :duplicate_bag,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    otp_app = data.world_module.__otp_app__()

    token =
      Ecspanse.Util.encode_payload(otp_app, %{
        otp_app: data.world_module.__otp_app__(),
        world_name: data.world_name,
        world_pid: self(),
        supervisor: data.supervisor,
        components_state_ets_name: components_state_ets_name,
        resources_state_ets_name: resources_state_ets_name,
        events_ets_name: events_ets_name
      })

    state = %State{
      token: token,
      id: data.id,
      world_name: data.world_name,
      world_pid: self(),
      world_module: data.world_module,
      supervisor: data.supervisor,
      components_state_ets_name: components_state_ets_name,
      resources_state_ets_name: resources_state_ets_name,
      events_ets_name: events_ets_name,
      last_frame_monotonic_time: Elixir.System.monotonic_time(:millisecond),
      delta: 0,
      fps_limit: data.world_module.__fps_limit__()
    }

    # Special system that creates the default resources
    create_default_resources_system =
      %System{
        module: Ecspanse.System.CreateDefaultResources,
        queue: :startup_systems,
        execution: :sync
      }
      |> add_run_conditions([])

    %World{operations: operations} = apply(state.world_module, :setup, [%World{}])
    operations = operations ++ [{:add_system, create_default_resources_system}]

    state = operations |> Enum.reverse() |> apply_operations(state)

    send(self(), {:run, data.events})

    {:ok, state}
  end

  @impl true
  def handle_call(:fetch_token, _from, %State{status: :startup_systems} = state) do
    {:reply, {:error, :not_ready}, state}
  end

  def handle_call(:fetch_token, _from, state) do
    {:reply, {:ok, state.token}, state}
  end

  def handle_call(:debug, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:shutdown, state) do
    {:stop, :shutdown, state}
  end

  @impl true
  def handle_info({:run, system_start_events}, state) do
    # startup_events passed as options in the Ecspanse.new/2 function
    event_batches =
      system_start_events
      |> Enum.sort_by(fn {_k, v} -> v.inserted_at end, &</2)
      |> batch_events([])

    state = %{
      state
      | scheduled_systems: state.startup_systems,
        frame_data: %Frame{event_batches: event_batches, token: state.token}
    }

    send(self(), :run_next_system)
    {:noreply, state}
  end

  def handle_info(:start_frame, state) do
    # Collect Memoize garbage
    Task.start(fn ->
      Memoize.garbage_collect()
    end)

    # use monotonic time
    # https://til.hashrocket.com/posts/k6kydebcau-precise-timings-with-monotonictime
    frame_monotonic_time = Elixir.System.monotonic_time(:millisecond)
    delta = frame_monotonic_time - state.last_frame_monotonic_time

    # inserted_at is the System time in milliseconds when the event was created
    event_batches =
      :ets.tab2list(state.events_ets_name)
      |> Enum.sort_by(fn {_k, v} -> v.inserted_at end, &</2)
      |> batch_events([])

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
          event_batches: event_batches,
          token: state.token
        }
    }

    # Delete all events from the ETS table
    :ets.delete_all_objects(state.events_ets_name)

    Process.send_after(self(), :finish_frame_timer, round(limit))
    send(self(), :run_next_system)
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
          prepare_system_process(state, system)
          system.module.run(state.frame_data)
        end)

      Task.await(task)
    end)
  end

  ### HELPER ###

  defp run_system(system, state) do
    %Task{ref: ref} =
      Task.async(fn ->
        prepare_system_process(state, system)
        system.module.run(state.frame_data)
        :finished_system_execution
      end)

    ref
  end

  # This happens in the System process
  defp prepare_system_process(state, system) do
    Process.put(:ecs_process_type, :system)
    Process.put(:token, state.token)
    Process.put(:system_execution, system.execution)
    Process.put(:system_module, system.module)
    Process.put(:locked_components, system.module.__locked_components__())
    Process.put(:components_state_ets_name, state.components_state_ets_name)
    Process.put(:resources_state_ets_name, state.resources_state_ets_name)
    Process.put(:events_ets_name, state.events_ets_name)
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
    try do
      if system_module.__ecs_type__() == :system do
        :ok
      else
        raise "validation error"
      end
    rescue
      _ -> reraise ArgumentError, "The module #{inspect(system_module)} must be a System"
    end

    if MapSet.member?(state.system_modules, system_module) do
      raise "System #{inspect(system_module)} already exists. World systems must be unique."
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
    # when one or more locked components are entity specific {component, entity_type_component}
    # need to verify also that the generic component is not present as locked in the batch
    # this adds quite a bit of extra complexity
    # it needs to check also for new components not to be present in the batch as entity scoped components

    # Example
    # System1 lock_components [Component1]
    # and
    # System2 lock_components [{Component1, EntityTypeComponent}]
    # should NOT be allowed in the same batch

    system_locked_components = system.module.__locked_components__()

    entity_scoped_components =
      Enum.filter(system_locked_components, &match?({_, entity_type: _}, &1))
      |> Enum.map(&elem(&1, 0))

    batch_locked_components =
      Enum.map(batch, & &1.module.__locked_components__()) |> List.flatten()

    entity_scoped_batched =
      Enum.filter(batch_locked_components, &match?({_, entity_type: _}, &1))
      |> Enum.map(&elem(&1, 0))

    if batch_locked_components --
         system_locked_components --
         entity_scoped_components ==
         batch_locked_components and
         entity_scoped_batched --
           system_locked_components ==
           entity_scoped_batched do
      updated_batch = batch ++ [system]
      # return result
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

  defp add_run_conditions(system, opts) do
    run_in_state =
      case Keyword.get(opts, :run_in_state, []) do
        state when is_atom(state) -> [state]
        states when is_list(states) -> states
      end

    run_in_state_functions =
      Enum.map(run_in_state, fn state ->
        {Ecspanse.Util, :run_system_in_state, [state]}
      end)

    run_not_in_state =
      case Keyword.get(opts, :run_not_in_state, []) do
        state when is_atom(state) -> [state]
        states when is_list(states) -> states
      end

    run_not_in_state_functions =
      Enum.map(run_not_in_state, fn state ->
        {Ecspanse.Util, :run_system_not_in_state, [state]}
      end)

    run_if =
      case Keyword.get(opts, :run_if, []) do
        {module, function} = condition when is_atom(module) and is_atom(function) -> [condition]
        conditions when is_list(conditions) -> conditions
      end

    run_if_functions =
      Enum.map(run_if, fn {module, function} ->
        {module, function, []}
      end)

    %System{
      system
      | run_conditions: run_in_state_functions ++ run_not_in_state_functions ++ run_if_functions
    }
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
        result = apply(module, function, [state.token | args])

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

  # merge the system options with the system set options
  defp merge_system_options(system_opts, system_set_opts)
       when is_list(system_opts) and is_map(system_set_opts) do
    system_set_opts = Map.values(system_set_opts) |> List.flatten() |> Enum.uniq()

    (system_opts ++ system_set_opts)
    |> Enum.group_by(fn {k, _v} -> k end, fn {_k, v} -> v end)
    |> Map.to_list()
  end

  defp batch_events([], batches), do: batches

  defp batch_events(events, batches) do
    current_events = Enum.uniq_by(events, fn {k, _v} -> k end)
    batch = Enum.map(current_events, fn {_, v} -> v end)
    remaining_events = events -- current_events
    batch_events(remaining_events, batches ++ [batch])
  end
end
