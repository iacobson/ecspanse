defmodule Ecspanse do
  @moduledoc """
  Ecspanse is an Entity Component System (ECS) library for Elixir, designed to manage game state and provide tools for measuring time and frame duration.
  It is not a game engine, but a flexible foundation for managing state and building game logic.

  The core structure of the Ecspanse library is:

  - `Ecspanse`: The main module used to configure and interact with the library.
  - `Ecspanse.Server`: The server orchestrates the execution of systems and the storage of components, resources, and events.
  - `Ecspanse.Entity`: A simple struct with an ID, serving as a holder for components.
  - `Ecspanse.Component`: A struct that may hold state information or act as a simple label for an entity.
  - `Ecspanse.System`: Holds the application core logic. Systems run every frame, either synchronously or asynchronously.
  - `Ecspanse.Resource`: Global state storage, similar to components but not tied to a specific entity. Resources can only be created, updated, and deleted by synchronously executed systems.
  - `Ecspanse.Query`: A tool for retrieving entities, components, or resources.
  - `Ecspanse.Command`: A mechanism for changing component and resource state. They can only be triggered from a system.
  - `Ecspanse.Event`: A mechanism for triggering events, which can be listened to by systems. It is the way to communicate externally with the systems.

  ## Usage

  To use Ecspanse, a module needs to be created that `use Ecspanse`. This implements the `Ecspanse` behaviour, so the `setup/1` callback must be defined. All the systems and their execution order are defined in the `setup/1` callback.

  ### Examples

  ```elixir
  defmodule TestServer1 do
    use Ecspanse, fps_limit: 60

    def setup(data) do
      world
      |> Ecspanse.Server.add_startup_system(Demo.Systems.SpawnHero)
      |> Ecspanse.Server.add_frame_start_system(Demo.Systems.PurchaseItem)
      |> Ecspanse.Server.add_system(Demo.Systems.MoveHero)
      |> Ecspanse.Server.add_frame_end_system(Ecspanse.System.Timer)
      |> Ecspanse.Server.add_shutdown_system(Demo.Systems.Cleanup)
    end
  end
  ```

  ## Configuration

  The following configuration options are available:
  - `:fps_limit` (optional) - the maximum number of frames per second. Defaults to :unlimited.


  # Special Resources

  Some special resources, such as `State` or `FPS`, are created by default by the framework.

  """

  require Logger

  alias __MODULE__
  alias Ecspanse.Util

  defmodule Data do
    @moduledoc """
    The `Data` module defines a struct that holds the state of the Ecspanse initialization process.
    This struct is passed to the `setup/1` callback, which is used to define the running systems.
    After the initialization process the `Data` struct is not relevant anymore.
    """

    @typedoc """
    The data used for the Ecspanse initialization process.
    """
    @type t :: %__MODULE__{
            operations: operations(),
            system_set_options: map()
          }

    @type operation ::
            {:add_system, Ecspanse.System.system_queue(), Ecspanse.System.t()}
            | {:add_system, :batch_systems, Ecspanse.System.t(), opts :: keyword()}
    @type operations :: list(operation())

    defstruct operations: [], system_set_options: %{}
  end

  @doc """
  The `setup/1` callback is called on Ecspanse startup and is the place to define the running systems.
  It takes an `Ecspanse.Data` struct as an argument and returns an updated struct.

  ## Examples

  ```elixir
  defmodule MyProject do
    use Ecspanse

    @impl Ecspanse
    def setup(%Ecspanse.Data{} = data) do
      data
      |> Ecspanse.Server.add_system(Demo.Systems.MoveHero)
    end
  end
  ```
  """
  @callback setup(Ecspanse.Data.Ecspanse.Data.t()) :: Ecspanse.Data.Ecspanse.Data.t()

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      @behaviour Ecspanse

      fps_limit = Keyword.get(opts, :fps_limit, :unlimited)

      if fps_limit && not (is_integer(fps_limit) || fps_limit == :unlimited) do
        raise ArgumentError,
              "If set, the option :fps_limit must be a non negative integer in the Server module #{inspect(__MODULE__)}"
      end

      Module.register_attribute(__MODULE__, :fps_limit, accumulate: false)
      Module.put_attribute(__MODULE__, :fps_limit, fps_limit)

      # THIS WILL BE THE MIX ENV OF THE PROJECT USING ECSPANSE, NOT ECSPANSE ITSELF
      if Mix.env() == :test do
        # Do not start the "real" server in test mode
        @doc false
        def child_spec(arg) do
          if arg == :test do
            payload = %{
              ecspanse_module: __MODULE__,
              fps_limit: @fps_limit
            }

            spec = %{
              id: __MODULE__,
              start: {Ecspanse.Server, :start_link, [payload]},
              restart: :permanent
            }
          else
            %{
              id: UUID.uuid4(),
              start: {Ecspanse.TestServer, :start_link, [nil]},
              restart: :temporary
            }
          end
        end
      else
        @doc false
        def child_spec(arg) do
          payload = %{
            ecspanse_module: __MODULE__,
            fps_limit: @fps_limit
          }

          spec = %{
            id: __MODULE__,
            start: {Ecspanse.Server, :start_link, [payload]},
            restart: :permanent
          }
        end
      end
    end
  end

  @doc """
  Schedules a startup system.

  A startup system runs only once during the Ecspanse startup process. Startup systems do not take any options.

  ## Examples

    ```elixir
    Ecspanse.add_startup_system(ecspanse_data, Demo.Systems.SpawnHero)
    ```
  """
  @spec add_startup_system(Ecspanse.Data.t(), system_module :: module()) :: Ecspanse.Data.t()
  def add_startup_system(%Ecspanse.Data{operations: operations} = data, system_module) do
    system = %Ecspanse.System{
      module: system_module,
      queue: :startup_systems,
      execution: :sync,
      run_conditions: []
    }

    %Ecspanse.Data{data | operations: [{:add_system, system} | operations]}
  end

  @doc """
  Schedules a frame start system to be executed each frame during the game loop.

  A frame start system is executed synchronously at the beginning of each frame.
  Sync systems are executed in the order they were added.

  ## Options

  - See the `add_system/3` function for more information about the options.

  ## Examples

    ```elixir
    Ecspanse.add_frame_start_system(ecspanse_data, Demo.Systems.PurchaseItem)
    ```
  """

  @spec add_frame_start_system(Ecspanse.Data.t(), system_module :: module(), opts :: keyword()) ::
          Ecspanse.Data.t()
  def add_frame_start_system(
        %Ecspanse.Data{operations: operations} = data,
        system_module,
        opts \\ []
      ) do
    opts = merge_system_options(opts, data.system_set_options)

    if Keyword.get(opts, :run_after) do
      Logger.warning(
        "The :run_after option is ignored by sync running systems. Those will always run in the order they were added to the data."
      )
    end

    system =
      %Ecspanse.System{module: system_module, queue: :frame_start_systems, execution: :sync}
      |> add_run_conditions(opts)

    %Ecspanse.Data{data | operations: [{:add_system, system} | operations]}
  end

  @doc """
  Schedules an async system to be executed each frame during the game loop.

  ## Options

  - `:run_in_state` - a list of states in which the system should run.
  - `:run_not_in_state` - a list of states in which the system should not run.
  - `:run_if` - a list of tuples containing the module and function that define a condition for running the system. Eg. `[{MyModule, :my_function}]`. The function must return a boolean.
  - `:run_after` - only for async systems - a system or list of systems that must run before this system.

  ## Order of execution

  Systems are executed each frame during the game loop. Sync systems run in the order they were added to the data's operations list.
  Async systems are grouped in batches depending on the componets they are locking.
  See the `Ecspanse.System` module for more information about component locking.

  The order in which async systems run can pe specified using the `run_after` option.
  This option takes a system or list of systems that must be run before the current system.

  When using the `run_after: SystemModule1` or `run_after: [SystemModule1, SystemModule2]` option, the following rules apply:
  - The system(s) specified in `run_after` must be already scheduled. This prevents circular dependencies.
  - There is a deliberate choice to allow **only the `run_after`** ordering option. While a `run_before` option would simplify some relations, it can also introduce circular dependencies.

  Example of circular dependency:
  - System A
  - System B, run_before: System A
  - System C, run_after: System A, run_before: System B

  ## Examples

    ```elixir
    Ecspanse.add_system(
      ecspanse_data,
      Demo.Systems.MoveHero,
      run_in_state: [:play],
      run_after: [Demo.Systems.RestoreEnergy]
    )
    ```
  """
  @spec add_system(Ecspanse.Data.t(), system_module :: module(), opts :: keyword()) ::
          Ecspanse.Data.t()
  def add_system(%Ecspanse.Data{operations: operations} = data, system_module, opts \\ []) do
    opts = merge_system_options(opts, data.system_set_options)

    after_system = Keyword.get(opts, :run_after)

    run_after =
      case after_system do
        nil -> []
        after_systems when is_list(after_systems) -> after_systems
        after_system when is_atom(after_system) -> [after_system]
      end

    system =
      %Ecspanse.System{
        module: system_module,
        queue: :batch_systems,
        execution: :async,
        run_after: run_after
      }
      |> add_run_conditions(opts)

    %Ecspanse.Data{data | operations: [{:add_system, system} | operations]}
  end

  @doc """
  Schedules a frame end system to be executed each frame during the game loop.

  A frame end system is executed synchronously at the end of each frame.
  Sync systems are executed in the order they were added.

  ## Options

  - See the `add_system/3` function for more information about the options.

  ## Examples

    ```elixir
    Ecspanse.add_frame_end_system(ecspanse_data, Ecspanse.Systems.Timer)
    ```
  """
  @spec add_frame_end_system(Ecspanse.Data.t(), system_module :: module(), opts :: keyword()) ::
          Ecspanse.Data.t()
  def add_frame_end_system(
        %Ecspanse.Data{operations: operations} = data,
        system_module,
        opts \\ []
      ) do
    opts = merge_system_options(opts, data.system_set_options)

    if Keyword.get(opts, :run_after) do
      Logger.warning(
        "The :run_after option is ignored by sync running systems. Those will always run in the order they were added to the data."
      )
    end

    system =
      %Ecspanse.System{module: system_module, queue: :frame_end_systems, execution: :sync}
      |> add_run_conditions(opts)

    %Ecspanse.Data{data | operations: [{:add_system, system} | operations]}
  end

  @doc """
  Schedules a shutdown system.

  A shutdown system runs only once when the Ecspanse.Server terminates. Shutdown systems do not take any options.
  This is useful for cleaning up or saving the game state.

  ## Examples

    ```elixir
    Ecspanse.add_shutdown_system(ecspanse_data, Demo.Systems.Cleanup)
    ```
  """
  @spec add_shutdown_system(Ecspanse.Data.t(), system_module :: module()) :: Ecspanse.Data.t()
  def add_shutdown_system(%Ecspanse.Data{operations: operations} = data, system_module) do
    system = %Ecspanse.System{
      module: system_module,
      queue: :shutdown_systems,
      execution: :sync,
      run_conditions: []
    }

    %Ecspanse.Data{data | operations: [{:add_system, system} | operations]}
  end

  @doc """
  Convenient way to group together related systems.

  New systems can be added to the set using the `add_system_*` functions.
  System sets can also be nested.


  ## Options

  The set options that applied on top of each system options in the set.
  - See the `add_system/3` function for more information about the options.

  ## Examples

  ```elixir
  defmodule Demo do
    use Ecspanse

    @impl Ecspanse
    def setup(data) do
      data
      |> Ecspanse.add_system_set({Demo.HeroSystemSet, :setup}, [run_in_state: :play])
    end

    defmodule HeroSystemSet do
      def setup(data) do
        data
        |> Ecspanse.add_system(Demo.Systems.MoveHero, [run_after: Demo.Systems.RestoreEnergy])
        |> Ecspanse.add_system_set({Demo.ItemsSystemSet, :setup})
      end
    end

    defmodule ItemsSystemSet do
      def setu(data) do
        data
        |> Ecspanse.add_system(Demo.Systems.PickupItem)
      end
    end
  end
  ```
  """
  @spec add_system_set(Ecspanse.Data.t(), {module(), function :: atom}, opts :: keyword()) ::
          Ecspanse.Data.t()
  def add_system_set(data, {module, function}, opts \\ []) do
    # add the system set options to the data
    # the Server system_set_options is a map with the key {module, function} for every system set
    data = %Ecspanse.Data{
      data
      | system_set_options: Map.put(data.system_set_options, {module, function}, opts)
    }

    data = apply(module, function, [data])

    # remove the system set options from the data
    %Ecspanse.Data{
      data
      | system_set_options: Map.delete(data.system_set_options, {module, function})
    }
  end

  @doc """
  Retrieves the Ecspanse Server process PID.
  If the data process is not found, it returns an error.

  ## Examples

    ```elixir
    Ecspanse.fetch_pid()
    {:ok, %{name: data_name, pid: data_pid}}
    ```
  """
  @spec fetch_pid() ::
          {:ok, pid()} | {:error, :not_found}
  def fetch_pid do
    case Process.whereis(Ecspanse.Server) do
      pid when is_pid(pid) ->
        {:ok, pid}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Queues an event to be processed in the next frame.

  ## Options

  - `:batch_key` - A key for grouping multiple similar events in different batches within the same frame.
  The event scheduler groups the events into batches by unique `{EventModule, batch_key}` combinations.
  In most cases, the key may be an entity ID that either triggers or is impacted by the event.
  Defaults to `default`, meaning that similar events will be placed in separate batches.

  ## Examples

    ```elixir
      Ecspanse.event({Demo.Events.MoveHero, direction: :up},  batch_key: hero_entity.id)
    ```
  """
  @spec event(
          Ecspanse.Event.event_spec(),
          opts :: keyword()
        ) :: :ok
  def event(event_spec, opts \\ []) do
    batch_key = Keyword.get(opts, :batch_key, "default")

    event = prepare_event(event_spec, batch_key)

    :ets.insert(Util.events_ets_table(), event)
    :ok
  end

  defp prepare_event(event_spec, batch_key) do
    {event_module, key, event_payload} =
      case event_spec do
        {event_module, event_payload}
        when is_atom(event_module) and is_list(event_payload) ->
          validate_event(event_module)
          {event_module, batch_key, event_payload}

        event_module when is_atom(event_module) ->
          validate_event(event_module)
          {event_module, batch_key, []}
      end

    event_payload =
      event_payload
      |> Keyword.put(:inserted_at, System.os_time())

    {{event_module, key}, struct!(event_module, event_payload)}
  end

  defp validate_event(event_module) do
    Ecspanse.Util.validate_ecs_type(
      event_module,
      :event,
      ArgumentError,
      "The module #{inspect(event_module)} must be a Event"
    )
  end

  # merge the system options with the system set options
  defp merge_system_options(system_opts, system_set_opts)
       when is_list(system_opts) and is_map(system_set_opts) do
    system_set_opts = Map.values(system_set_opts) |> List.flatten() |> Enum.uniq()

    (system_opts ++ system_set_opts)
    |> Enum.group_by(fn {k, _v} -> k end, fn {_k, v} -> v end)
    |> Enum.map(fn {k, v} -> {k, v |> List.flatten() |> Enum.uniq()} end)
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

    %Ecspanse.System{
      system
      | run_conditions: run_in_state_functions ++ run_not_in_state_functions ++ run_if_functions
    }
  end
end
