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
  defmemo components_state_ets_table,
    permanent: true,
    max_waiter: 1000,
    waiter_sleep_ms: 0 do
    Agent.get(:ecspanse_ets_tables, fn state ->
      state.components_state_ets_table
    end)
  end

  @doc false
  defmemo resources_state_ets_table,
    permanent: true,
    max_waiter: 1000,
    waiter_sleep_ms: 0 do
    Agent.get(:ecspanse_ets_tables, fn state ->
      state.resources_state_ets_table
    end)
  end

  @doc false
  defmemo events_ets_table,
    permanent: true,
    max_waiter: 1000,
    waiter_sleep_ms: 0 do
    Agent.get(:ecspanse_ets_tables, fn state ->
      state.events_ets_table
    end)
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

    :ets.select(components_state_ets_table(), f)
    |> Enum.group_by(fn {k, _v} -> k end, fn {_k, v} -> v end)
  end

  @doc false
  # Returns a list of tuples with entity_id, component_tags and component_state
  # Example: [{"entity_id", [:tag1,:tag2], %MyComponent{foo: :bar}}]
  # Cannot be memoized as it returns the componet state, so it will be invalidated every frame multiple times.

  # This may need to be optimized in the future.
  # I tried the same approach as with components, not to return the state but the Component module and memoize
  # Then in the query to fetch the state for each component, but the framerate dropped by around 20%
  def list_entities_components_tags do
    f =
      Ex2ms.fun do
        {{entity_id, _component_module}, component_tags, component_state}
        when component_tags != [] ->
          {entity_id, component_tags, component_state}
      end

    :ets.select(components_state_ets_table(), f)
  end

  def list_entities_components_tags(%Ecspanse.Entity{id: entity_id}) do
    f =
      Ex2ms.fun do
        {{id, _component_module}, component_tags, component_state}
        when component_tags != [] and id == ^entity_id ->
          {id, component_tags, component_state}
      end

    :ets.select(components_state_ets_table(), f)
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
  def invalidate_cache do
    Memoize.invalidate(Ecspanse.Query)
    Memoize.invalidate(Ecspanse.Util, :list_entities_components)
  end

  @doc false
  def invalidate_query_cache do
    Memoize.invalidate(Ecspanse.Query)
  end
end
