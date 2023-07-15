defmodule Ecspanse do
  @moduledoc """


  Ecspanse is an Entity Component System (ECS) library for Elixir, designed to manage game state and provide tools for measuring time and frame duration.
  It is not a game engine, but a flexible foundation for building game logic.

  The core structure of the Ecspanse library is:

  - `Ecspanse.Server`: The data orchestrates the execution of systems and the storage of entities, components, and resources.
  Each data schedules system execution and listens for events.
  - `Ecspanse.Entity`: A simple struct with an ID, serving as a holder for components.
  - `Ecspanse.Component`: A struct that holds state information.
  - `Ecspanse.System`: The core logic of the library. Systems are configured for each data and run every frame, either synchronously or asynchronously.
  - `Ecspanse.Resource`: Global state storage, similar to components but not tied to a specific entity. Resources can only be created, updated, and deleted by synchronously executed systems.
  - `Ecspanse.Query`: A tool for retrieving entities, components, or resources.
  - `Ecspanse.Command`: A mechanism for changing component and resource state, which can only be triggered from a system.
  - `Ecspanse.Event`: A mechanism for triggering events, which can be listened to by systems. It is the way to communicate externally with the data.

  # Usage

  A module needs to be created that `use Ecspanse`. This implements the `Ecspanse` behaviour, so the `setup/1` callback must be defined.
  All their systems and their execution order are defined in the `setup/1` callback.

  ## Example

  ```elixir
  defmodule TestServer1 do
    use Ecspanse, fps_limit: 60

    def setup(data) do
      world
      |> Ecspanse.Server.add_system(TestSystem5)
      |> Ecspanse.Server.add_frame_end_system(TestSystem3)
      |> Ecspanse.Server.add_frame_start_system(TestSystem2)
      |> Ecspanse.Server.add_startup_system(TestSystem1)
      |> Ecspanse.Server.add_shutdown_system(TestSystem4)
    end
  end
  ```

  ## Configuration

  The following configuration options are available:
  - `:fps_limit` - optional - the maximum number of frames per second. Defaults to `:unlimited`.


  # Special Resources

  Some special resources, such as `State` or `FPS`, are created by default by the framework.

  """

  require Logger

  alias __MODULE__
  alias Ecspanse.Util

  defmodule Data do
    @moduledoc """
    The Data struct holds the state the Ecspanse initialization process.
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
  The `setup/1` callback is called when the data is created and is the place to setup the running systems in the data.

  ## Parameters

  - `data` - the current state of the Ecspanse initialization data.

  ## Returns

  The updated data needed for initialization.

  ## Example

  ```elixir
  defmodule MyServer do
    use Server

    @impl Server
    def setup(data) do
      data
      |> Ecspanse.add_startup_event(MyStartupEvent)
      |> Ecspanse.add_startup_event({MyOtherStartupEvent, value: :foo})
      |> Ecspanse.add_system(MySystem)
      |> Ecspanse.add_frame_end_system(MyFrameEndSystem)
      |> Ecspanse.add_frame_start_system(MyFrameStartSystem)
      |> Ecspanse.add_startup_system(MyStartupSystem)
      |> Ecspanse.add_shutdown_system(MyShutdownSystem)
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

      @doc false
      def child_spec(arg) do
        if Mix.env() == :test && arg != :test do
          %{
            id: UUID.uuid4(),
            start: {Ecspanse.TestServer, :start_link, [nil]},
            restart: :temporary
          }
        else
          payload = %{
            ecspanse_module: __MODULE__,
            fps_limit: @fps_limit
          }

          %{
            id: __MODULE__,
            start: {Ecspanse.Server, :start_link, [payload]},
            restart: :permanent
          }
        end
      end
    end
  end

  @doc """
  Adds a startup system to the data.

  A startup system is run only once when the data is created. Startup systems do not take options.

  ## Parameters

  - `data` - the current state of the data.
  - `system_module` - the module that defines the startup system.

  ## Returns

  The updated state of the data.
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

  Adds a frame start system to the data.

  A frame start system is executed synchronously at the beginning of each frame.
  Sync systems are executed in the order they were added to the data.

  ## Parameters

  - `data` - the current state of the data.
  - `system_module` - the module that defines the frame start system.
  - `opts` - optional - a keyword list of options to apply to the system. See the `add_system/3` function for more information about the options.

  ## Returns

  The updated state of the data.
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
  Adds an async system to the data, to be executed asynchronously each frame during the game loop.

  The `add_system/3` function takes the data as an argument and returns the updated data. Inside the function, a new system is created using the `System` struct and added to the data's operations list.

  ## Parameters

  - `data` - the current state of the data.
  - `system_module` - the module that defines the system.
  - `opts` - optional - a keyword list of options to apply to the system.

  ## Options

  - `:run_in_state` - a list of states in which the system should be run.
  - `:run_not_in_state` - a list of states in which the system should not be run.
  - `:run_if` - a tuple containing the module and function that define a condition for running the system. Eg. `[{Module, :function}]`
  - `:run_after` - a system or list of systems that must be run before this system.

  ## Returns

  The updated state of the data.

  ## Order of execution
  You can specify the order in which systems are run using the `run_after` option. This option takes a system or list of systems that must be run before this system.

  When using the `run_after: SystemModule1` or `run_after: [SystemModule1, SystemModule2]` option, the following rules apply:

  - The system(s) specified in `run_after` must already be added to the data. This prevents circular dependencies.
  - There is a deliberate choice to allow only the `run_after` option. While a `before` option would simplify some relations, it can also introduce circular dependencies.

  For example, consider the following systems:

  - System A
  - System B, which must be run before System A
  - System C, which must be run after System A and before System B

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

  Adds a frame end system to the data.

  A frame end system is executed synchronously at the end of each frame.
  Sync systems are executed in the order they were added to the data.

  ## Parameters

  - `data` - the current state of the data.
  - `system_module` - the module that defines the frame start system.
  - `opts` - optional - a keyword list of options to apply to the system. See the `add_system/3` function for more information about the options.

  ## Returns

  The updated state of the data.

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
  Run only once on Server shutdown
  Does not take options

  Adds a shutdown system to the data.

  A shudtown system is run only once when the data is terminated. Shutdown systems do not take options.

  ## Parameters

  - `data` - the current state of the data.
  - `system_module` - the module that defines the startup system.

  ## Returns

  The updated state of the data.
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

  Adds a system set to the data.

  A system set is a way to group systems together. The `opts` parameter is a keyword list of options that are applied on top of the system's options inside the set. System sets can also be nested.
  See the `add_system/3` function for more information about the options.

  The `add_system_set/3` function takes the data as an argument and returns the updated data. Inside the function, new systems can be added using the `add_system_*` functions.

  ## Parameters

  - `data` - the current state of the data.
  - `{module, function}` - the module and function that define the system set.
  - `opts` - optional - a keyword list of options to apply to the system set.

  ## Returns

  The updated state of the data.

  ## Example

  ```elixir
  defmodule MySetup do
    use Ecspanse

    @impl Ecspanse
    def setup(data) do
      data
      |> Ecspanse.add_system_set({MySystemSet, :my_func}, [run_in_state: :my_state])
    end
  end

  defmodule MySystemSet do
    def my_func(data) do
      data
      |> Ecspanse.add_system(MySystem, [option: "value"])
      |> Ecspanse.add_system_set({MyNestedSystemSet, :my_func})
    end
  end

  defmodule MyNestedSystemSet do
    def my_func(data) do
      data
      |> Ecspanse.add_system(MyNestedSystem)
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

      iex> Ecspanse.fetch_pid()
      {:ok, %{name: data_name, pid: data_pid}}

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
  Queues a data event to be processed in the next frame.

  The first argument is an event spec.

  ## Options

  - `:batch_key` - A key for grouping multiple similar events in different batches within the same frame.
  The data groups the events into batches with unique `{EventModule, batch_key}` combinations.
  In most cases, the key may be an entity ID that either triggers or is impacted by the event.
  Defaults to "default", meaning that similar events will be processed in separate batches.

  ## Examples

      iex> Ecspanse.event(MyEventModule,  batch_key: my_entity.id)
      :ok

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
