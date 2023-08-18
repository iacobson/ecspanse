defmodule Ecspanse.System do
  @moduledoc """
  The system implements the logic and behaviors of the application
  by manipulating the state of the components.
  The systems are defined by invoking `use Ecspanse.System` in their module definition.

  The system modules must implement the
  `c:Ecspanse.System.WithoutEventSubscriptions.run/1` or
  `c:Ecspanse.System.WithEventSubscriptions.run/2` callbacks,
  depending if the system subscribes to certain events or not.
  The return value of the `run` function is ignored.

  The Ecspanse systems run either synchronously or asynchronously,
  as scheduled in the `c:Ecspanse.setup/1` callback.

  Systems are the sole mechanism through which the state of components can be altered.
  Running commands outside of a system is not allowed.

  Resources can be created, updated, and deleted only by systems that are executed synchronously.

  There are some special systems that are created automatically by the framework:
  - `Ecspanse.System.CreateDefaultResources` - startup system that creates the default framework resources.
  - `Ecspanse.System.Debug` - used by the `debug/0` function.
  - `Ecspanse.System.Timer` - tracks and updates all components using the `Ecspanse.Template.Component.Timer` template.
  - `Ecspanse.System.TrackFPS` - tracks and updates the `Ecspanse.Resource.FPS` resource.

  ## Options

  - `:lock_components` - a list of component modules
  that will be locked for the duration of the system execution.
  - `:event_subscriptions` - a list of event modules that the system subscribes to.


  ## Component locking

  Component locking is required only for async systems to avoid race conditions.

  For async systems, any components that are to be modified, created, or deleted,
  must be locked in the `lock_components` option. Otherwise, the operation will fail.
  Wherever it makes sense, it is recommended to lock also components that are queried but not modified,
  as they could be modified by other systems.

  Not all async systems run concurrently. The systems are grouped in batches,
  based on the components they lock.

  ## Event subscriptions

  The event subscriptions enables a system to execute solely in response to certain specified events.

  The `c:Ecspanse.System.WithEventSubscriptions.run/2` callback is triggered
  for every occurrence of an event type to which the system has subscribed.
  These callbacks execute concurrently to enhance performance.
  However, they are grouped based on their batch keys (see `Ecspanse.event/2` options)
  as a safeguard against potential race conditions.

  ## Examples

    ```elixir
    defmodule Demo.Systems.Move do
      @moduledoc "An async system locking components, that subscribes to an event"
      use Ecspanse.System,
        lock_components: [Demo.Components.Position],
        event_subscriptions: [Demo.Events.Move]

      def run(%Demo.Events.Move{entity_id: entity_id, direction: direction}, frame) do
        # move logic
      end
    end

    defmodule Demo.Systems.SpawnEnemy do
      @moduledoc "A sync system that does not need to lock components, and it is not subscribed to any events"
      use Ecspanse.System

      def run(frame) do
        # spawn logic
      end
    end
    ```
  """

  # The System process stores several keys to be used by the Commands and Queries.
  # - ecs_process_type (:system)
  # - system_execution :sync | :async
  # - locked_components
  # - system_module

  @type system_queue ::
          :startup_systems
          | :frame_start_systems
          | :batch_systems
          | :frame_end_systems
          | :shutdown_systems

  @type t :: %__MODULE__{
          module: module(),
          queue: system_queue(),
          execution: :sync | :async,
          run_after: list(system_module :: module()),
          run_conditions: list({module(), atom()})
        }

  @enforce_keys [:module, :queue, :execution]
  defstruct module: nil,
            queue: nil,
            execution: nil,
            run_after: [],
            run_conditions: []

  @doc """
  Utility function. Gives the current process `Ecspanse.System` abilities to execute commands.

  This is a powerful tool for testing and debugging,
  as the promoted process can change the components and resources state
  without having to be scheduled like a regular system.

  See `Ecspanse.TestServer` for more details.

  > #### This function is intended for use only in testing and development environments.  {: .warning}
  """
  @spec debug() :: :ok
  def debug do
    Process.put(:ecs_process_type, :system)
    Process.put(:system_execution, :sync)
    Process.put(:system_module, Ecspanse.System.Debug)
    Process.put(:locked_components, Ecspanse.System.Debug.__locked_components__())

    :ok
  end

  @doc """
  Allows running async code inside a system.

  Because commands can run only from inside a system,
  running commands in a Task, for example, is not possible.
  The `execute_async/3` is a wrapper around `Elixir.Task.async_stream/3`
  and is built exactly for this purpose. It allows running commands in parallel.

  The result of the processing is ignored. So the function is suitable for cases
  when the result is not important. For example, updating components for a list of entities.

  > #### Info  {: .info}
  > This function is already imported for all modules that `use Ecspanse.System`

  ## Options
  - `:concurrent` - the number of concurrent tasks to run.
  Defaults to the number of schedulers online.
  See `Elixir.Task.async_stream/5` options for more details.

  > #### use with care  {: .error}
  > While the locked components ensure that no other system is modifying
  > the same components at the same time, the `execute_async/3` does not offer
  > any such guarantees inside the same system.
  >
  > For example, the same component can be modified concurrently, leading to
  > race conditions and inconsistent state.

  ## Examples

    ```elixir
      Ecspanse.System.execute_async(
        enemy_entities,
        fn enemy_entity ->
          # update the enemy components
        end,
        concurrent: length(enemy_entities) + 1
      )
    ```
  """
  @spec execute_async(Enumerable.t(), (term() -> term()), keyword()) :: :ok
  def execute_async(enumerable, fun, opts \\ [])

  def execute_async(enumerable, fun, opts)
      when is_function(fun, 1) and is_list(opts) do
    concurrent = Keyword.get(opts, :concurrent, System.schedulers_online())

    system_process_dict = Process.get()

    enumerable
    |> Task.async_stream(
      fn e ->
        Enum.each(system_process_dict, fn {k, v} -> Process.put(k, v) end)
        fun.(e)
      end,
      ordered: false,
      max_concurrency: concurrent
    )
    |> Stream.run()
  end

  defmodule WithoutEventSubscriptions do
    @moduledoc """
    Systems that run every frame and do not depend on any event.
    """

    @doc """
    Runs every frame for the current system.
    The return value is ignored.

    It recives the current `t:Ecspanse.Frame.t/0` struct as the only argument.
    """
    @callback run(Ecspanse.Frame.t()) :: any()
  end

  defmodule WithEventSubscriptions do
    @moduledoc """
    Systems that run only if specific events are triggered.
    """

    @doc """
    Runs only if the system is subscribed to the triggering event.
    The return value is ignored.

    It recives the triggering event struct as the first argument
    and the current `t:Ecspanse.Frame.t/0` struct as the second argument.
    """
    @callback run(event :: struct(), Ecspanse.Frame.t()) :: any()
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      import Ecspanse.System, only: [execute_async: 3, execute_async: 2]
      locked_components = Keyword.get(opts, :lock_components, [])
      event_modules = Keyword.get(opts, :event_subscriptions, [])

      case event_modules do
        [] ->
          @behaviour Ecspanse.System.WithoutEventSubscriptions

        event_modules when is_list(event_modules) ->
          Ecspanse.Util.validate_events(event_modules)
          @behaviour Ecspanse.System.WithEventSubscriptions

        event_modules ->
          raise ArgumentError,
                "#{inspect(__MODULE__)} :event_subscriptions option must be a list of event modules. Got: #{inspect(event_modules)}"
      end

      Enum.each(locked_components, fn
        component ->
          Ecspanse.Util.validate_ecs_type(
            component,
            :component,
            ArgumentError,
            "All modules provided to the #{inspect(__MODULE__)} System :lock_components option must be Components. #{inspect(component)} is not a Component"
          )
      end)

      # IMPORTANT
      # even components that are not directly updated must be locked.
      # for example a component may be created or deleted
      # or we want to make sure some component state does not change durin the system execution
      Module.register_attribute(__MODULE__, :ecs_type, accumulate: false)
      Module.register_attribute(__MODULE__, :locked_components, accumulate: false)
      Module.put_attribute(__MODULE__, :ecs_type, :system)
      Module.put_attribute(__MODULE__, :locked_components, locked_components)

      ### Internal functions ###
      # not exposed in the docs

      case event_modules do
        [] ->
          @doc false
          def schedule_run(frame) do
            run(frame)
          end

        event_modules ->
          @doc false
          def schedule_run(frame) do
            Enum.each(frame.event_batches, fn events ->
              events
              |> Enum.filter(&(&1.__struct__ in unquote(event_modules)))
              |> Ecspanse.System.execute_async(&run(&1, frame), concurrent: length(events) + 1)
            end)
          end
      end

      @doc false
      def __ecs_type__ do
        @ecs_type
      end

      @doc false
      def __locked_components__ do
        @locked_components
      end
    end
  end
end
