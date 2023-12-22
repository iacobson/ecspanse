defmodule Ecspanse.Util do
  @moduledoc false
  # utility functions to be used inside the library
  # should not be exposed in the docs

  use Memoize
  require Ex2ms

  @doc false
  def build_entity(id) do
    Ecspanse.Entity |> struct(id: id)
  end

  @doc false
  def components_state_ets_table do
    :ets_ecspanse_components_state
  end

  @doc false
  def resources_state_ets_table do
    :ets_ecspanse_resources_state
  end

  @doc false
  def events_ets_table do
    [{:current, current_table}] = :ets.lookup(dual_events_ets_table(), :current)
    current_table
  end

  @doc false
  def events_ets_tables do
    [:ets_ecspanse_events_1, :ets_ecspanse_events_2]
  end

  @doc false
  def dual_events_ets_table do
    :ets_dual_events_ets_table
  end

  @doc false
  def swithch_events_ets_table do
    [{:current, current_table}] = :ets.lookup(dual_events_ets_table(), :current)
    [new_table] = events_ets_tables() -- [current_table]

    :ets.insert(
      dual_events_ets_table(),
      {:current, new_table}
    )
  end

  @doc false
  # Returns a map with entity_id as key and a list of component modules as value
  # Example %{"entity_id" => [Component1, Component2]}
  defmemo list_entities_components,
    max_waiter: 1000,
    waiter_sleep_ms: 0 do
    f =
      Ex2ms.fun do
        {{entity_id, component_module}, _component_tags, _component_state} ->
          {entity_id, component_module}
      end

    try do
      :ets.select(components_state_ets_table(), f)
      |> Enum.group_by(fn {k, _v} -> k end, fn {_k, v} -> v end)
    rescue
      e ->
        case :ets.info(components_state_ets_table()) do
          :undefined -> reraise server_not_started_error(), __STACKTRACE__
          _ -> reraise e, __STACKTRACE__
        end
    end
  end

  @doc false
  # Optimization for filtering components by tags
  # The operation is expensive when checking all components in an application with many components
  defmemo filter_entities_components_tags(tags),
    max_waiter: 1000,
    waiter_sleep_ms: 0 do
    tags_set = MapSet.new(tags)

    list_entities_components_tags()
    |> Stream.filter(fn {_entity_id, _component_module, component_tags_set} ->
      MapSet.subset?(tags_set, component_tags_set)
    end)
    |> Enum.to_list()
  end

  @doc false
  # Implementation dedicated to the timer components, and the timer system
  # The cache is invalidated only if timer components are added or removed
  defmemo filter_timer_entities_components_tags,
    max_waiter: 1000,
    waiter_sleep_ms: 0 do
    timer_component_tag = Ecspanse.Template.Component.Timer.timer_component_tag()
    tags_set = MapSet.new([timer_component_tag])

    list_entities_components_tags()
    |> Stream.filter(fn {_entity_id, _component_module, component_tags_set} ->
      MapSet.subset?(tags_set, component_tags_set)
    end)
    |> Enum.to_list()
  end

  defp list_entities_components_tags do
    empty_set = MapSet.new()

    f =
      Ex2ms.fun do
        {{entity_id, component_module}, component_tags_set, _component_state}
        when component_tags_set != ^empty_set ->
          {entity_id, component_module, component_tags_set}
      end

    try do
      :ets.select(components_state_ets_table(), f)
    rescue
      e ->
        case :ets.info(components_state_ets_table()) do
          :undefined -> reraise server_not_started_error(), __STACKTRACE__
          _ -> reraise e, __STACKTRACE__
        end
    end
  end

  @doc false
  # Returns a list of tuples with entity_id, component_tags_set and component_state
  # Example: [{"entity_id", [:tag1,:tag2], %MyComponent{foo: :bar}}]
  # Cannot be memoized as it returns the componet state, so it will be invalidated every frame multiple times.
  def list_entities_tags_state(%Ecspanse.Entity{id: entity_id}) do
    empty_set = MapSet.new()

    f =
      Ex2ms.fun do
        {{id, _component_module}, component_tags_set, component_state}
        when component_tags_set != ^empty_set and id == ^entity_id ->
          {id, component_tags_set, component_state}
      end

    try do
      :ets.select(components_state_ets_table(), f)
    rescue
      e ->
        case :ets.info(components_state_ets_table()) do
          :undefined -> reraise server_not_started_error(), __STACKTRACE__
          _ -> reraise e, __STACKTRACE__
        end
    end
  end

  @doc false
  def run_system_in_state(run_in_state) do
    {:ok, %Ecspanse.Resource.State{value: state}} =
      Ecspanse.Query.fetch_resource(Ecspanse.Resource.State)

    run_in_state == state
  end

  @doc false
  def run_system_not_in_state(run_not_in_state) do
    not run_system_in_state(run_not_in_state)
  end

  @doc false
  def validate_events(event_modules) do
    Enum.each(event_modules, fn event_module ->
      validate_ecs_type(
        event_module,
        :event,
        ArgumentError,
        "The module #{inspect(event_module)} must be an event."
      )
    end)

    :ok
  end

  @doc false
  def validate_ecs_type(module, type, exception, attributes) do
    # try, because an invalid module would not implement this function
    try do
      if is_atom(module) && Code.ensure_compiled!(module) && module.__ecs_type__() == type do
        :ok
      else
        raise "validation error"
      end
    rescue
      _exception ->
        reraise exception, attributes, __STACKTRACE__
    end
  end

  @doc false
  def server_not_started_error do
    "Ecspanse Server not started. The module invoking `use Ecspanse` needs to be added to the aplication supervision tree."
  end

  @doc false
  def invalidate_cache do
    Memoize.invalidate(Ecspanse.Query)
    Memoize.invalidate(Ecspanse.Util, :list_entities_components)
  end

  @doc false
  def invalidate_tags_cache do
    Memoize.invalidate(Ecspanse.Util, :filter_entities_components_tags)
  end

  @doc false
  def invalidate_timer_tag_cache do
    Memoize.invalidate(Ecspanse.Util, :filter_timer_entities_components_tags)
  end

  @doc false
  def invalidate_query_cache do
    Memoize.invalidate(Ecspanse.Query)
  end
end
