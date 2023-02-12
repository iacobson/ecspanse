defmodule Ecspanse.System do
  @moduledoc """
  TODO

  All components that are to be modified, created or deleted, must be defined in the `lock_components` option.
  Some systems may not need to lock any components, in which case the option can be omitted.

  The `lock_components` is a list of either:
  - Component modules.
  - `{Component, entity_type: EntityTypeComponent}` tuples,
  where `Component` is the component module
  and `EntityTypeComponent` is the component module that defines the entity with access mode `:entity_type`


  For systems that are executed synchronously, the `lock_components` option is not necessary.
  If provided, it is ignored and a warning is logged.

  """

  # The System process stores several keys to be used by the Commands and Queries.
  # - ecs_process_type (:system)
  # - token
  # - system_execution :sync | :async
  # - locked_components
  # - system_module
  # - components_state_ets_name
  # - resources_state_ets_name
  # - events_ets_name

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
  TODO - Add description and usage

  Use when the result of the processing is not important. Eg update components for a list of entities.

  The function is already imported in the System modules that `use Ecspanse.System`

  Options
  - concurrent :: integer() - The number of concurrent tasks to run. Defaults to the number of schedulers online.
  This is using the Elixir `Task.async_stream/3 |> Stream.run/1` functions.
  More details about concurrency: https://hexdocs.pm/elixir/1.12/Task.html#async_stream/3

  **Tip** use with care. While the locked components ensure that no other system is modifying the same components at the same time,
  the `execute_async/3` does not offer any guarantees inside the system.
  For example, trying to update the same components in multiple asyunc functions may result in race conditions and unexpected state.
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

  @doc """
  TODO
  The function may return any value. The value is ignored.
  Recives a Frame struct as argument.
  """
  @callback run(Ecspanse.World.Frame.t()) :: any()

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      import Ecspanse.System, only: [execute_async: 3, execute_async: 2]
      @behaviour Ecspanse.System
      locked_components = Keyword.get(opts, :lock_components, [])

      Enum.each(locked_components, fn
        {component, entity_type: entity_type_component}
        when is_atom(component) and is_atom(entity_type_component) ->
          Code.ensure_compiled!(component)
          Code.ensure_compiled!(entity_type_component)

          unless component.__ecs_type__() == :component do
            raise ArgumentError,
                  "All modules provided to the #{inspect(__MODULE__)} System :lock_components option must be Components. #{inspect(component)} is not a Component"
          end

          unless entity_type_component.__ecs_type__() == :component do
            raise ArgumentError,
                  "All modules provided to the #{inspect(__MODULE__)} System :lock_components option must be Components. #{inspect(entity_type_component)} is not a Component"
          end

          unless entity_type_component.__component_access_mode__() == :entity_type do
            raise ArgumentError,
                  "System #{inspect(__MODULE__)}. When providing a tuple to the :lock_components option, the second element must be a component with access mode :entity_type. #{inspect(entity_type_component)} does not have access mode :entity_type"
          end

        component when is_atom(component) ->
          Code.ensure_compiled!(component)

          unless component.__ecs_type__() == :component do
            raise ArgumentError,
                  "All modules provided to the #{inspect(__MODULE__)} System :lock_components option must be Components. #{inspect(component)} is not a Component"
          end
      end)

      # IMPORTANT
      # both write and readonly components that will be modified should be locked
      # for example, a readonly component cannot be edited, but can be deleted or created
      Module.register_attribute(__MODULE__, :ecs_type, accumulate: false)
      Module.register_attribute(__MODULE__, :locked_components, accumulate: false)
      Module.put_attribute(__MODULE__, :ecs_type, :system)
      Module.put_attribute(__MODULE__, :locked_components, locked_components)

      ### Internal functions ###
      # not exposed in the docs

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
