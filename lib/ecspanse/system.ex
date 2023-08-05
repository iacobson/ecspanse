defmodule Ecspanse.System do
  @moduledoc """
  TODO

  All components that are to be modified, created or deleted, must be defined in the `lock_components` option.
  Some systems may not need to lock any components, in which case the option can be omitted.

  The `lock_components` is a list of Component modules.


  The `event_subscriptions` option is used to define a system that will be executed only when specific events are triggered.
  The system runs for every event of the specified types. The evens run in paralled, but batched by event keys, to avoid race conditions.
  The event itself is passed to the system as the first argument in the `run/2` function


  For systems that are executed synchronously, the `lock_components` option is not necessary.
  If provided, it is ignored and a warning is logged.


  Resources can be created, updated and deleted only by systems that are executed synchronously.

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

  WARNING: to be used only for development and testing.

  Gives any process Ecspanse.System abilities (eg. executing commands).
  This is a powerful tool for testing and debugging, as the promoted process
  can change the components and resources state without having to be scheduled like a regular system.
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
  TODO - Add description and usage

  Use when the result of the processing is not important. Eg update components for a list of entities.

  The function is already imported in the System modules that `use Ecspanse.System`

  Options
  - concurrent :: integer() - The number of concurrent tasks to run. Defaults to the number of schedulers online.
  This is using the Elixir `Task.async_stream/3 |> Stream.run/1` functions.
  More details about concurrency: https://hexdocs.pm/elixir/1.12/Task.html#async_stream/3

  **Tip** use with care. While the locked components ensure that no other system is modifying the same components at the same time,
  the `execute_async/3` does not offer any guarantees inside the system.
  For example, trying to update the same components in multiple async functions may result in race conditions and unexpected state.
  On the other hand, it can improve a lot the speed of the system execution.
  For example, a large list of components that belong to different entities and are not interdependent, can be updated in parallel.

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
    Systems that do not depend on any event.
    """

    @doc """
    TODO
    The function may return any value. The value is ignored.
    Recives the current Frame struct as argument.
    """
    @callback run(Ecspanse.Frame.t()) :: any()
  end

  defmodule WithEventSubscriptions do
    @moduledoc """
    Systems that need to be executed for a specific event.
    """

    @doc """
    TODO
    The function may return any value. The value is ignored.
    Recives the triggering Event and the current Frame struct as arguments.
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
          # at this point, the events for entities that do not exist
          # have already been filtered out in the Server batching
          def schedule_run(frame) do
            run(frame)
          end

        event_modules ->
          @doc false
          # at this point, the events for entities that do not exist
          # have already been filtered out in the Server batching
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
