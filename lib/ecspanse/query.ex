defmodule Ecspanse.Query do
  @moduledoc """
  # TODO
  """

  use Memoize

  require Ex2ms

  alias __MODULE__
  alias Ecspanse.Entity
  alias Ecspanse.Component
  alias Ecspanse.Util

  @type t :: %Query{
          return_entity: boolean(),
          select: list(component_module :: module()),
          select_optional: list(component_module :: module()),
          or:
            list(
              with_components: list(component_module :: module()),
              without_components: list(component_module :: module())
            ),
          for_entities: list(Ecspanse.Entity.t()),
          not_for_entities: list(Ecspanse.Entity.t()),
          for_children_of: list(Ecspanse.Entity.t()),
          for_parents_of: list(Ecspanse.Entity.t())
        }

  @enforce_keys [:select]
  defstruct [
    :return_entity,
    :select,
    :select_optional,
    :or,
    :for_entities,
    :not_for_entities,
    :for_children_of,
    :for_parents_of
  ]

  defmodule Error do
    @moduledoc false
    defexception [:message]

    @impl true
    def exception(message) do
      msg = """
      Message: #{message}
      """

      msg = maybe_add_system_info(msg)

      %Error{message: msg}
    end

    # if the query is called from a system, add the system module to the error message
    defp maybe_add_system_info(msg) do
      system_module = Process.get(:system_module)

      system_msg = """
      Calling System Module: #{inspect(system_module)}
      """

      if system_module do
        msg <> system_msg
      else
        msg
      end
    end
  end

  @doc """
  # TODO
  document options and filters


  Clarification: select/2 first argument is a tuple, that would return the components in the same order
  EVERY optional component should be marked as `opt: Component`
  eg: `select({Comp1, Comp2, opt: Comp3, opt: Comp4})`


  **VERY IMPORTANT** The optional components need to be added at the end of the tuple,
  otherwise the result ordering witll be wrong.

  """
  @spec select(component_modules :: tuple(), keyword()) :: t()
  defmemo select(component_modules_tuple, filters \\ []), max_waiter: 1000, waiter_sleep_ms: 0 do
    comp = Tuple.to_list(component_modules_tuple) |> List.flatten()

    # The order is essential here, because the result will be pattern_matched on the initial tuple
    {select_comp, select_opt_comp} =
      Enum.reduce(comp, {[], []}, fn
        {:opt, opt_comp}, {select_comp, select_opt_comp} when is_atom(opt_comp) ->
          {select_comp, select_opt_comp ++ [opt_comp]}

        comp, {select_comp, select_opt_comp} when is_atom(comp) ->
          {select_comp ++ [comp], select_opt_comp}

        error, _acc ->
          raise Error, "Expected to be a Component or [opt: Component], got: `#{inspect(error)}`"
      end)

    {return_entity, select_comp} =
      case List.first(select_comp) do
        Entity ->
          {true, List.delete_at(select_comp, 0)}

        _ ->
          {false, select_comp}
      end

    :ok = validate_components(select_comp)
    :ok = validate_components(select_opt_comp)

    # composing component queries from mandatory select components, plus filters
    # there can be multiple `or` filters for the same query (with: [:comp1, :comp2], or_with: [:comp3, :comp4])
    or_component_filters =
      compose_component_filters(
        select_comp,
        [Keyword.get(filters, :with, []) | Keyword.get_values(filters, :or_with)],
        []
      )

    :ok = validate_filters(filters)

    for_entities = Keyword.get(filters, :for, []) |> Enum.uniq()
    not_for_entities = Keyword.get(filters, :not_for, []) |> Enum.uniq()
    for_children_of = Keyword.get(filters, :for_children_of, []) |> Enum.uniq()
    for_parents_of = Keyword.get(filters, :for_parents_of, []) |> Enum.uniq()

    :ok = validate_entities(for_entities)

    %Query{
      return_entity: return_entity,
      select: select_comp,
      select_optional: select_opt_comp,
      or: or_component_filters,
      for_entities: for_entities,
      not_for_entities: not_for_entities,
      for_children_of: for_children_of,
      for_parents_of: for_parents_of
    }
  end

  @doc """
  Retrieve a stream of entities that match the query tuple
  """
  @spec stream(t()) :: Enumerable.t()
  def stream(query) do
    components_state_ets_table =
      Util.components_state_ets_table()

    # filter by entity ids, if any. Retruns a stream
    entities_with_components_stream =
      entities_with_components_stream(query)

    # filters by with/without components. Returns the entity ids
    entity_ids = filter_by_components(query.or, entities_with_components_stream, [])

    # retrieve the queried components for each entity
    map_components(
      query.return_entity,
      query.select,
      query.select_optional,
      entity_ids,
      components_state_ets_table
    )
  end

  @doc """
  TODO
  """
  @spec one(t()) :: components_state :: tuple() | nil
  def one(query) do
    case stream(query) |> Enum.to_list() do
      [result_tuple] -> result_tuple
      [] -> nil
      results -> raise Error, "Expected to return one result, got: `#{inspect(results)}`"
    end
  end

  @doc """
    TODO
  Returns the Entity struct as long as it has at least one component.
  """
  @spec fetch_entity(Ecspanse.Entity.id()) :: {:ok, t()} | {:error, :not_found}
  def fetch_entity(entity_id) do
    f =
      Ex2ms.fun do
        {{^entity_id, _component_module, _component_groups}, _component_state} -> ^entity_id
      end

    result = :ets.select(Util.components_state_ets_table(), f, 1)

    case result do
      {[^entity_id], _} ->
        {:ok, Ecspanse.Entity.build(entity_id)}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  TODO
  """
  @spec get_component_entity(component_state :: struct()) ::
          Ecspanse.Entity.t()
  def get_component_entity(component) do
    :ok = validate_components([component])
    component.__meta__.entity
  end

  @doc """
  TODO
  Returns a list of entities that are children of the given entity
  """
  @spec list_children(Ecspanse.Entity.t()) :: list(Ecspanse.Entity.t())
  defmemo list_children(%Entity{id: entity_id}), max_waiter: 1000, waiter_sleep_ms: 0 do
    case :ets.lookup(Util.components_state_ets_table(), {entity_id, Component.Children, []}) do
      [{_key, %Component.Children{entities: children_entities}}] -> children_entities
      [] -> []
    end
  end

  @doc """
  TODO
  Returns a list of entities that are parents of the given entity
  """
  @spec list_parents(Ecspanse.Entity.t()) :: list(Ecspanse.Entity.t())
  defmemo list_parents(%Entity{id: entity_id}), max_waiter: 1000, waiter_sleep_ms: 0 do
    case :ets.lookup(Util.components_state_ets_table(), {entity_id, Component.Parents, []}) do
      [{_key, %Component.Parents{entities: parents_entities}}] -> parents_entities
      [] -> []
    end
  end

  @doc """
  TODO
  Fetches components in a group, for all entities.
  """
  @spec list_group_components(group :: atom()) ::
          list(components_state :: struct())
  def list_group_components(group) do
    Ecspanse.Util.list_entities_components_groups()
    |> Stream.filter(fn {_entity_id, groups, _state} -> group in groups end)
    |> Enum.map(fn {_entity_id, _groups, state} -> state end)
  end

  @doc """
  TODO
  Fetches components in a group, for an entity.
  """
  @spec list_group_components(Ecspanse.Entity.t(), group :: atom()) ::
          list(components_state :: struct())
  def list_group_components(entity, group) do
    Ecspanse.Util.list_entities_components_groups()
    |> Stream.filter(fn {entity_id, groups, _state} ->
      entity_id == entity.id && group in groups
    end)
    |> Enum.map(fn {_entity_id, _groups, state} -> state end)
  end

  @doc """
  TODO
  Fetches the component state for the given entity.
  """
  @spec fetch_component(Ecspanse.Entity.t(), module()) ::
          {:ok, component_state :: struct()} | {:error, :not_found}
  def fetch_component(%Entity{id: entity_id}, component_module) do
    case :ets.lookup(
           Util.components_state_ets_table(),
           {entity_id, component_module, component_module.__component_groups__()}
         ) do
      [{_key, component}] -> {:ok, component}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  TODO
  Fetches the components state for the given entity.
  The components modules are passed as a tuple. And the result is a tuple with the components state.
  """
  @spec fetch_components(Ecspanse.Entity.t(), component_modules :: tuple()) ::
          {:ok, components_state :: tuple()} | {:error, :not_found}
  def fetch_components(%Entity{} = entity, component_modules_tuple) do
    query = select(component_modules_tuple, for: [entity])

    case one(query) do
      result when is_tuple(result) -> {:ok, result}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  TODO
  """
  @spec has_component?(Ecspanse.Entity.t(), module()) :: boolean()
  def has_component?(entity, component_module) when is_atom(component_module) do
    has_components?(entity, [component_module])
  end

  @doc """
  TODO
  """
  @spec has_components?(Ecspanse.Entity.t(), list(module())) :: boolean()
  defmemo has_components?(entity, component_module_list)
          when is_list(component_module_list),
          max_waiter: 1000,
          waiter_sleep_ms: 0 do
    entities_components = Ecspanse.Util.list_entities_components()

    component_module_list -- Map.get(entities_components, entity.id, []) == []
  end

  @doc """
  TODO
  """
  @spec is_child_of?(parent: Ecspanse.Entity.t(), child: Ecspanse.Entity.t()) :: boolean()
  defmemo is_child_of?(parent: %Entity{} = parent, child: %Entity{} = child),
    max_waiter: 1000,
    waiter_sleep_ms: 0 do
    parents = list_parents(child)
    parent in parents
  end

  @doc """
  TODO
  """
  @spec is_parent_of?(parent: Ecspanse.Entity.t(), child: Ecspanse.Entity.t()) :: boolean()
  defmemo is_parent_of?(parent: %Entity{} = parent, child: %Entity{} = child),
    max_waiter: 1000,
    waiter_sleep_ms: 0 do
    children = list_children(parent)
    child in children
  end

  @spec has_children_with_component?(Ecspanse.Entity.t(), module()) ::
          boolean()
  def has_children_with_component?(entity, component_module) do
    has_children_with_components?(entity, [component_module])
  end

  @doc """
  TODO
  """
  @spec has_children_with_components?(Ecspanse.Entity.t(), list(module())) ::
          boolean()
  defmemo has_children_with_components?(entity, component_module_list)
          when is_list(component_module_list) do
    components =
      select(List.to_tuple(component_module_list), for_children_of: [entity])
      |> stream()
      |> Enum.to_list()

    Enum.any?(components)
  end

  @doc """
  TODO
  """
  @spec has_parents_with_component?(Ecspanse.Entity.t(), module()) ::
          boolean()
  def has_parents_with_component?(entity, component_module) do
    has_parents_with_components?(entity, [component_module])
  end

  @doc """
  TODO
  """
  @spec has_parents_with_components?(Ecspanse.Entity.t(), list(module())) ::
          boolean()
  defmemo has_parents_with_components?(entity, component_module_list)
          when is_list(component_module_list) do
    components =
      select(List.to_tuple(component_module_list), for_parents_of: [entity])
      |> stream()
      |> Enum.to_list()

    Enum.any?(components)
  end

  @doc """
  TODO
  Fetches a resource state
  """
  @spec fetch_resource(resource_module :: module()) ::
          {:ok, resource_state :: struct()} | {:error, :not_found}
  def fetch_resource(resource_module) do
    case :ets.lookup(Util.resources_state_ets_table(), resource_module) do
      [{_key, resource}] -> {:ok, resource}
      [] -> {:error, :not_found}
    end
  end

  # Helper

  defp compose_component_filters(_select_components, [], acc), do: acc

  defp compose_component_filters(select_components, [or_components | rest], acc) do
    {with_components, without_components} =
      case List.last(or_components) do
        {:without, list_of_comp} when is_list(list_of_comp) ->
          {List.delete_at(or_components, -1), list_of_comp}

        {:without, comp} when is_atom(comp) ->
          {List.delete_at(or_components, -1), [comp]}

        _ ->
          {or_components, []}
      end

    :ok = validate_components(with_components)
    :ok = validate_components(without_components)

    compose_component_filters(select_components, rest, [
      [
        with_components: Enum.uniq(select_components ++ with_components),
        without_components: Enum.uniq(without_components)
      ]
      | acc
    ])
  end

  defp entities_with_components_stream(query) do
    cond do
      not Enum.empty?(query.for_entities) ->
        filter_for_entities(query.for_entities)

      not Enum.empty?(query.not_for_entities) ->
        filter_not_for_entities(query.not_for_entities)

      not Enum.empty?(query.for_children_of) ->
        entities_with_components_stream_for_children(query)

      not Enum.empty?(query.for_parents_of) ->
        entities_with_components_stream_for_parents(query)

      true ->
        filter_for_entities([])
    end
  end

  defp entities_with_components_stream_for_children(query) do
    case list_children_entities(query.for_children_of) do
      [] -> []
      entities -> filter_for_entities(entities)
    end
  end

  defp entities_with_components_stream_for_parents(query) do
    case list_parents_entities(query.for_parents_of) do
      [] -> []
      entities -> filter_for_entities(entities)
    end
  end

  defp list_children_entities(for_children_entities) do
    select({Component.Children}, for: for_children_entities)
    |> stream()
    |> Stream.map(fn {children} -> children.entities end)
    |> Stream.concat()
  end

  defp list_parents_entities(for_parent_entities) do
    select({Component.Parents}, for: for_parent_entities)
    |> stream()
    |> Stream.map(fn {parents} -> parents.entities end)
    |> Stream.concat()
  end

  defp filter_for_entities([]) do
    Ecspanse.Util.list_entities_components()
    |> Stream.map(fn {k, v} -> {k, v} end)
  end

  defp filter_for_entities(entities) do
    entity_ids = Enum.map(entities, & &1.id)

    Ecspanse.Util.list_entities_components()
    |> Stream.filter(fn {entity_id, _component_modules} -> entity_id in entity_ids end)
  end

  defp filter_not_for_entities([]) do
    Ecspanse.Util.list_entities_components()
    |> Stream.map(fn {k, v} -> {k, v} end)
  end

  defp filter_not_for_entities(entities) do
    entity_ids = Enum.map(entities, & &1.id)

    Ecspanse.Util.list_entities_components()
    |> Stream.reject(fn {entity_id, _component_modules} -> entity_id in entity_ids end)
  end

  defp filter_by_components([], _entities_with_components_stream, entity_ids) do
    Enum.uniq(entity_ids)
  end

  defp filter_by_components(
         [[with_components: with_components, without_components: without_components] | rest],
         entities_with_components_stream,
         entity_ids
       ) do
    new_entity_ids =
      entities_with_components_stream
      |> Stream.filter(fn {_entity_id, component_modules} ->
        with_components -- component_modules == [] and
          without_components -- component_modules == without_components
      end)
      |> Stream.map(fn {entity_id, _component_modules} -> entity_id end)

    filter_by_components(
      rest,
      entities_with_components_stream,
      Stream.concat(entity_ids, new_entity_ids)
    )
  end

  defp map_components(
         return_entity,
         select_components,
         select_optional_components,
         entity_ids,
         components_state_ets_table
       ) do
    entity_ids
    |> Task.async_stream(
      fn entity_id ->
        {}
        |> map_entity(return_entity, entity_id)
        |> add_select_components(select_components, entity_id, components_state_ets_table)
        |> add_select_optional_components(
          select_optional_components,
          entity_id,
          components_state_ets_table
        )
      end,
      ordered: false,
      max_concurrency: length(entity_ids) + 1
    )
    |> Stream.map(fn {:ok, result} -> result end)
    |> Stream.reject(fn return_tuple ->
      :reject in Tuple.to_list(return_tuple)
    end)
  end

  # if the entity is part of the query, return the entity
  defp map_entity(select_tuple, return_entity, entity_id) do
    if return_entity do
      Tuple.append(select_tuple, Entity.build(entity_id))
    else
      select_tuple
    end
  end

  # add mandatory components to the select tuple
  defp add_select_components(select_tuple, comp_modules, entity_id, components_state_ets_table) do
    Enum.reduce(comp_modules, select_tuple, fn comp_module, acc ->
      case :ets.lookup(
             components_state_ets_table,
             {entity_id, comp_module, comp_module.__component_groups__()}
           ) do
        [{_key, comp_state}] -> Tuple.append(acc, comp_state)
        # checking for race conditions when a required component is removed during the query
        # the whole entity should be filtered out
        [] -> Tuple.append(acc, :reject)
      end
    end)
  end

  # add optional components
  defp add_select_optional_components(
         select_tuple,
         comp_modules,
         entity_id,
         components_state_ets_table
       ) do
    Enum.reduce(comp_modules, select_tuple, fn comp_module, acc ->
      case :ets.lookup(
             components_state_ets_table,
             {entity_id, comp_module, comp_module.__component_groups__()}
           ) do
        [{_key, comp_state}] -> Tuple.append(acc, comp_state)
        [] -> Tuple.append(acc, nil)
      end
    end)
  end

  # Validations

  defp validate_filters(filters) do
    res =
      [
        Keyword.get(filters, :for),
        Keyword.get(filters, :not_for),
        Keyword.get(filters, :for_children_of),
        Keyword.get(filters, :for_parents_of)
      ]
      |> Enum.reject(&is_nil/1)

    if length(res) > 1 do
      raise Error,
            "Combining the following filters is not allowed: :for, :not_for, :for_children_of, :for_parents_of"
    else
      :ok
    end
  end

  defp validate_entities(entities) do
    unless is_list(entities) do
      raise Error, "Expected `for:` entities to be a list, got: `#{Kernel.inspect(entities)}`"
    end

    non_enitites = Enum.reject(entities, &match?(%Entity{}, &1))

    case non_enitites do
      [] ->
        :ok

      _ ->
        raise Error,
              "Expected to be `Ecspanse.Entity.t()` types, got: `#{Kernel.inspect(non_enitites)}`"
    end
  end

  # accepts both list of modules and list of component state structs
  defp validate_components(components) do
    component_modules =
      Enum.map(
        components,
        fn
          module when is_atom(module) -> module
          struct when is_struct(struct) -> struct.__struct__
        end
      )

    Enum.each(component_modules, fn component_module ->
      Ecspanse.Util.validate_ecs_type(
        component_module,
        :component,
        Error,
        "Expected Component, got: `#{Kernel.inspect(component_module)}`"
      )
    end)

    :ok
  end
end
