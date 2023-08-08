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
          for_descendants_of: list(Ecspanse.Entity.t()),
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
    :for_descendants_of,
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
  @doc group: :generic
  @spec select(component_modules :: tuple(), keyword()) :: t()
  def select(component_modules_tuple, filters \\ []) do
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
    for_descendants_of = Keyword.get(filters, :for_descendants_of, []) |> Enum.uniq()
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
      for_descendants_of: for_descendants_of,
      for_parents_of: for_parents_of
    }
  end

  @doc """
  Retrieve a stream of entities that match the query tuple
  """
  @doc group: :generic
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
  @doc group: :generic
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
  @doc group: :entities
  @spec fetch_entity(Ecspanse.Entity.id()) :: {:ok, Ecspanse.Entity.t()} | {:error, :not_found}
  def fetch_entity(entity_id) do
    f =
      Ex2ms.fun do
        {{^entity_id, _component_module}, _component_tags, _component_state} -> ^entity_id
      end

    result = :ets.select(Util.components_state_ets_table(), f, 1)

    case result do
      {[^entity_id], _} ->
        {:ok, Ecspanse.Util.build_entity(entity_id)}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  TODO
  """
  @doc group: :entities
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
  @doc group: :relationships
  @spec list_children(Ecspanse.Entity.t()) :: list(Ecspanse.Entity.t())
  defmemo list_children(%Entity{id: entity_id}), max_waiter: 1000, waiter_sleep_ms: 0 do
    case :ets.lookup(Util.components_state_ets_table(), {entity_id, Component.Children}) do
      [{_key, _tags, %Component.Children{entities: children_entities}}] -> children_entities
      [] -> []
    end
  end

  @doc """
  TODO

  Returns a list of entities that are descendants of the given entity.
  That means the children of the entity and their children and so on.
  """
  @doc group: :relationships
  @spec list_descendants(Ecspanse.Entity.t()) :: list(Ecspanse.Entity.t())
  defmemo list_descendants(%Entity{} = entity), max_waiter: 1000, waiter_sleep_ms: 0 do
    list_descendants_entities([entity], [])
  end

  @doc """
  TODO
  Returns a list of entities that are parents of the given entity
  """
  @doc group: :relationships
  @spec list_parents(Ecspanse.Entity.t()) :: list(Ecspanse.Entity.t())
  defmemo list_parents(%Entity{id: entity_id}), max_waiter: 1000, waiter_sleep_ms: 0 do
    case :ets.lookup(Util.components_state_ets_table(), {entity_id, Component.Parents}) do
      [{_key, _tags, %Component.Parents{entities: parents_entities}}] -> parents_entities
      [] -> []
    end
  end

  @doc """
  TODO
  Lists tagged components, for all entities.
  The components need to be tagged with all the given tags to return.
  """
  @doc group: :tags
  @spec list_tagged_components(list(tag :: atom())) ::
          list(components_state :: struct())
  def list_tagged_components(tags) do
    :ok = validate_tags(tags)

    Ecspanse.Util.list_entities_components_tags()
    |> Stream.filter(fn {_entity_id, component_tags, _state} ->
      Enum.all?(tags, &(&1 in component_tags))
    end)
    |> Enum.map(fn {_entity_id, _tags, state} -> state end)
  end

  @doc """
  TODO
  Fetches tagged components, for a single entity.
  """
  @doc group: :tags
  @spec list_tagged_components_for_entity(Ecspanse.Entity.t(), list(tag :: atom())) ::
          list(components_state :: struct())
  def list_tagged_components_for_entity(entity, tags) do
    :ok = validate_entities([entity])
    :ok = validate_tags(tags)

    Ecspanse.Util.list_entities_components_tags(entity)
    |> Stream.filter(fn {_component_entity_id, component_tags, _state} ->
      Enum.all?(tags, &(&1 in component_tags))
    end)
    |> Enum.map(fn {_entity_id, _tags, state} -> state end)
  end

  @doc """
  TODO
  Fetches tagged components, for a list of entities.
  """
  @doc group: :tags
  @spec list_tagged_components_for_entities(list(Ecspanse.Entity.t()), list(tag :: atom())) ::
          list(components_state :: struct())
  def list_tagged_components_for_entities(entities, tags) do
    :ok = validate_entities(entities)
    :ok = validate_tags(tags)

    entity_ids = Enum.map(entities, & &1.id)

    Ecspanse.Util.list_entities_components_tags()
    |> Stream.filter(fn {component_entity_id, component_tags, _state} ->
      component_entity_id in entity_ids &&
        Enum.all?(tags, &(&1 in component_tags))
    end)
    |> Enum.map(fn {_entity_id, _tags, state} -> state end)
  end

  @doc """
  TODO
  Fetches tagged components, for the children of the given entity.
  """
  @doc group: :tags
  @spec list_tagged_components_for_children(Ecspanse.Entity.t(), list(tag :: atom())) ::
          list(components_state :: struct())
  def list_tagged_components_for_children(entity, tags) do
    case list_children(entity) do
      [] -> []
      [child] -> list_tagged_components_for_entity(child, tags)
      children -> list_tagged_components_for_entities(children, tags)
    end
  end

  @doc """
  TODO
  Fetches tagged components, for the descendants of the given entity.
  """
  @doc group: :tags
  @spec list_tagged_components_for_descendants(Ecspanse.Entity.t(), list(tag :: atom())) ::
          list(components_state :: struct())
  def list_tagged_components_for_descendants(entity, tags) do
    case list_descendants(entity) do
      [] -> []
      [descendant] -> list_tagged_components_for_entity(descendant, tags)
      descendants -> list_tagged_components_for_entities(descendants, tags)
    end
  end

  @doc """
  TODO
  Fetches tagged components, for the parents of the given entity.
  """
  @doc group: :tags
  @spec list_tagged_components_for_parents(Ecspanse.Entity.t(), list(tag :: atom())) ::
          list(components_state :: struct())
  def list_tagged_components_for_parents(entity, tags) do
    case list_parents(entity) do
      [] -> []
      [parent] -> list_tagged_components_for_entity(parent, tags)
      parents -> list_tagged_components_for_entities(parents, tags)
    end
  end

  @doc """
  TODO
  Fetches the component state for the given entity.
  """
  @doc group: :components
  @spec fetch_component(Ecspanse.Entity.t(), module()) ::
          {:ok, component_state :: struct()} | {:error, :not_found}
  def fetch_component(%Entity{id: entity_id}, component_module) do
    case :ets.lookup(Util.components_state_ets_table(), {entity_id, component_module}) do
      [{_key, _tags, component}] -> {:ok, component}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  TODO
  Fetches the components state for the given entity.
  The components modules are passed as a tuple. And the result is a tuple with the components state.
  """
  @doc group: :components
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
  @doc group: :components
  @spec has_component?(Ecspanse.Entity.t(), module()) :: boolean()
  def has_component?(entity, component_module) when is_atom(component_module) do
    has_components?(entity, [component_module])
  end

  @doc """
  TODO
  """
  @doc group: :components
  @spec has_components?(Ecspanse.Entity.t(), list(module())) :: boolean()
  def has_components?(entity, component_module_list)
      when is_list(component_module_list) do
    entities_components = Ecspanse.Util.list_entities_components()

    component_module_list -- Map.get(entities_components, entity.id, []) == []
  end

  @doc """
  TODO
  """
  @doc group: :relationships
  @spec is_child_of?(parent: Ecspanse.Entity.t(), child: Ecspanse.Entity.t()) :: boolean()
  def is_child_of?(parent: %Entity{} = parent, child: %Entity{} = child) do
    parents = list_parents(child)
    parent in parents
  end

  @doc """
  TODO
  """
  @doc group: :relationships
  @spec is_parent_of?(parent: Ecspanse.Entity.t(), child: Ecspanse.Entity.t()) :: boolean()
  def is_parent_of?(parent: %Entity{} = parent, child: %Entity{} = child) do
    children = list_children(parent)
    child in children
  end

  @doc """
  TODO
  """
  @doc group: :relationships
  @spec has_children_with_component?(Ecspanse.Entity.t(), module()) ::
          boolean()
  def has_children_with_component?(entity, component_module) do
    has_children_with_components?(entity, [component_module])
  end

  @doc """
  TODO
  """
  @doc group: :relationships
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
  @doc group: :relationships
  @spec has_parents_with_component?(Ecspanse.Entity.t(), module()) ::
          boolean()
  def has_parents_with_component?(entity, component_module) do
    has_parents_with_components?(entity, [component_module])
  end

  @doc """
  TODO
  """
  @doc group: :relationships
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
  @doc group: :resources
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

      not Enum.empty?(query.for_descendants_of) ->
        entities_with_components_stream_for_descendants(query)

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

  defp entities_with_components_stream_for_descendants(query) do
    case list_descendants_entities(query.for_descendants_of, []) do
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

  defp list_children_entities(entities) do
    select({Component.Children}, for: entities)
    |> stream()
    |> Stream.map(fn {children} -> children.entities end)
    |> Stream.concat()
  end

  defp list_descendants_entities([], acc) do
    acc
  end

  defp list_descendants_entities(entities, acc) do
    children =
      select({Component.Children}, for: entities)
      |> stream()
      |> Stream.map(fn {%Component.Children{entities: children}} -> children end)
      |> Enum.concat()

    # avoid circular dependencies
    children = Enum.uniq(children -- acc)
    acc = Enum.uniq(acc ++ children)

    list_descendants_entities(children, acc)
  end

  defp list_parents_entities(entities) do
    select({Component.Parents}, for: entities)
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
      Tuple.append(select_tuple, Util.build_entity(entity_id))
    else
      select_tuple
    end
  end

  # add mandatory components to the select tuple
  defp add_select_components(select_tuple, comp_modules, entity_id, components_state_ets_table) do
    Enum.reduce(comp_modules, select_tuple, fn comp_module, acc ->
      case :ets.lookup(components_state_ets_table, {entity_id, comp_module}) do
        [{_key, _tags, comp_state}] -> Tuple.append(acc, comp_state)
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
      case :ets.lookup(components_state_ets_table, {entity_id, comp_module}) do
        [{_key, _tags, comp_state}] -> Tuple.append(acc, comp_state)
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
            "Combining the following filters is not allowed: :for, :not_for, :for_children_of, :for_parents_of. Only one of them can be used at a time."
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

  defp validate_tags(tags) do
    unless is_list(tags) do
      raise Error, "Expected `tags:` to be a list, got: `#{Kernel.inspect(tags)}`"
    end

    non_tags = Enum.reject(tags, &is_atom/1)

    case non_tags do
      [] ->
        :ok

      _ ->
        raise Error,
              "Expected tags to be a list of atoms, got: `#{Kernel.inspect(non_tags)}`"
    end
  end
end
