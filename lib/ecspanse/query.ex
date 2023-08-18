defmodule Ecspanse.Query do
  @moduledoc """
  The `Ecspanse.Query` module provides a set of functions for querying entities, components and resources.

  The queries are read-only operations they do not modify the state of the components or resources.

  Queries can be run both from within the Ecspanse systems and from outside of the framework.
  """

  use Memoize

  require Ex2ms

  alias __MODULE__
  alias Ecspanse.Component
  alias Ecspanse.Entity
  alias Ecspanse.Util

  @typedoc "The query preparation struct."
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
  `select/2` is the most versatile function for querying entities and components.
  On its own, it will return an `Ecspanse.Query` struct that holds the query details.
  The struct needs to be passed to `Ecspanse.Query.stream/1` or `Ecspanse.Query.one/1` to get the results.

  ## Arguments

  ### 1. component_modules

  The first argument is a tuple of components to be selected. The query will return the components
  only for the entities that have **all** the components in the tuple.

  The entity can be queried as well by adding `Ecspanse.Entity` as the first element in the tuple.
  Also, optional components can be queries, by adding the `:opt` key.
  The optional components should be placed at the end of the tuple.

  The restults will be returned in the same order as the components in the tuple. This makes it easy to use pattern matching on the result.

  ### 2. filters

  The filters are optional. They can be used to further narrow down the results.

  - `:with` - a list of components that the entity must have in addition to the ones specified in the `component_modules` tuple.
  But those components will not be returned in the result. `:with` filter has one option: `:without` - a list of components that the entity must not have.
  - `:or_with` - similar to `:with`. It allows to specify multiple filters for the same query. Multiple `or_with` filters can be used in the same query.
  The results will be returned if the entity components match any of the filters.
  - `:for` - a list of `t:Ecspanse.Entity.t/0` that the query should be run for. The components will be returned only for those entities.
  - `:not_for` - a list of `t:Ecspanse.Entity.t/0` that the query should not be run for. The components will be returned for all entities except those.
  - `:for_children_of` - a list of `t:Ecspanse.Entity.t/0`. The components will be returned only for the children of those entities.
  - `:for_descendants_of` - a list of `t:Ecspanse.Entity.t/0`. The components will be returned only for all descendants of those entities.
  - `:for_parents_of` - a list of `t:Ecspanse.Entity.t/0`. The components will be returned only for the parents of those entities.

  > #### Info  {: .error}
  > Combining the following filters is not supported: `:for, :not_for, :for_children_of, :for_descendants_of, :for_parents_of`.
  > Only one of them can be used in a query. Otherwise it will rise an error.

  ## Examples
    ```elixir
    Ecspanse.Query.select({Ecspanse.Entity, Demo.Components.Health, opt: Demo.Components.Mana},
      with: [Demo.Components.Orc],
      or_with: [[Demo.Components.Wizard], without: [Demo.Components.WhiteMagic]],
      for_descendants_of: [enemy_clan_entity]
    )
    |> Ecspanse.Query.stream()
    |> Enum.to_list()
    ```
    a potential result may be:
    ```elixir
    [
      {orc_entity, %Demo.Components.Health{value: 100}, nil},
      {wizard_entity, %Demo.Components.Health{value: 60}, %Demo.Components.Mana{value: 200}}
    ]
    ```
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
  Returns a stream of components tuples for a `t:t/0` query.

  See the `select/2` function for more info.
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
  Returns a single tuple wiht components for a `t:t/0` query. Returns `nil` if no result was found. Raises if more than one entry.

  See the `select/2` function for more info.
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
  Fetches an `t:Ecspanse.Entity.t/0` by its ID.

  An entity exists only if it has at least one component.

    ## Examples

    ```elixir
    {:ok, %Ecspanse.Entity{}} = Ecspanse.Query.fetch_entity(hero_entity_id)
    ```
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
  Returns a component's entity.

  ## Examples

    ```elixir
    {:ok, %Ecspanse.Entity{}} = Ecspanse.Query.get_component_entity(hero_component)
    ```
  """
  @doc group: :entities
  @spec get_component_entity(component_state :: struct()) ::
          Ecspanse.Entity.t()
  def get_component_entity(component) do
    :ok = validate_components([component])
    component.__meta__.entity
  end

  @doc """
  Returns the list of child entities for the given entity.

  ## Examples

    ```elixir
    [sword_item_entity, magic_potion_entity] = Ecspanse.Query.list_children(hero_entity)
    ```
  """
  @doc group: :relationships
  @spec list_children(Ecspanse.Entity.t()) :: list(Ecspanse.Entity.t())
  def list_children(%Entity{} = entity) do
    memo_list_children(entity)
  end

  @doc false
  defmemo memo_list_children(%Entity{id: entity_id}), max_waiter: 1000, waiter_sleep_ms: 0 do
    case :ets.lookup(Util.components_state_ets_table(), {entity_id, Component.Children}) do
      [{_key, _tags, %Component.Children{entities: children_entities}}] -> children_entities
      [] -> []
    end
  end

  @doc """
  Returns the list of descendant entities for the given entity.
  That means the children of the entity and their children and so on.

  ## Examples

    ```elixir
    [inventory_entity, map_entity] = Ecspanse.Query.list_descendants(hero_entity)
    ```
  """
  @doc group: :relationships
  @spec list_descendants(Ecspanse.Entity.t()) :: list(Ecspanse.Entity.t())
  def list_descendants(%Entity{} = entity) do
    memo_list_descendants(entity)
  end

  @doc false
  defmemo memo_list_descendants(%Entity{} = entity), max_waiter: 1000, waiter_sleep_ms: 0 do
    list_descendants_entities([entity], [])
  end

  @doc """
  Returns the list of parent entities for the given entity.

  ## Examples

    ```elixir
    [hero_entity] = Ecspanse.Query.list_parents(inventory_entity)
    ```
  """
  @doc group: :relationships
  @spec list_parents(Ecspanse.Entity.t()) :: list(Ecspanse.Entity.t())
  def list_parents(%Entity{} = entity) do
    memo_list_parents(entity)
  end

  defmemo memo_list_parents(%Entity{id: entity_id}), max_waiter: 1000, waiter_sleep_ms: 0 do
    case :ets.lookup(Util.components_state_ets_table(), {entity_id, Component.Parents}) do
      [{_key, _tags, %Component.Parents{entities: parents_entities}}] -> parents_entities
      [] -> []
    end
  end

  @doc """
  Fetches an entity's component by a list of tags.
  Raises if more than one entry is found.

  > #### Note  {: .info}
  >
  > The project logic must ensure that only one component per entity is tagged with the given tags.

  ## Examples

    ```elixir
    {:ok, %Demo.Components.Paladin{} = hero_class_component} =
      Ecspanse.Query.fetch_tagged_component(hero_entity, [:class])
    ```
  """
  @doc group: :tags
  @spec fetch_tagged_component(Ecspanse.Entity.t(), list(tag :: atom())) ::
          {:ok, components_state :: struct()} | {:error, :not_found}
  def fetch_tagged_component(entity, tags) do
    components = list_tagged_components_for_entity(entity, tags)

    case components do
      [component] -> {:ok, component}
      [] -> {:error, :not_found}
      results -> raise Error, "Expected to return one result, got: `#{inspect(results)}`"
    end
  end

  @doc """
  Returns a list of components tagged with a list of tags for all entities.
  The components need to be tagged with all the given tags to return.

  ## Examples

    ```elixir
    [gold_component, gems_component] = Ecspanse.Query.list_tagged_components([:resource, :available])
    ```
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
  Returns a list of components tagged with a list of tags for a given entity.

  ## Examples

    ```elixir
    [gold_component, gems_component] = Ecspanse.Query.list_tagged_components_for_entity(hero_entity, [:resource, :available])
    ```
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
  Returns a list of components tagged with a list of tags for a given list of entities.
  The components are not grouped by entity, but returned as a flat list.

  ## Examples

    ```elixir
    [gold_component, gems_component, gems_component] = Ecspanse.Query.list_tagged_components_for_entities([hero_entity, enemy_entity], [:resource, :available])
    ```
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
  Returns a list of components tagged with a list of tags for the children of a given entity.

  ## Examples

    ```elixir
    [boots_component, compass_component] = Ecspanse.Query.list_tagged_components_for_children(hero_entity, [:inventory])
    ```
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
  Returns a list of components tagged with a list of tags for the descendants of a given entity.

  ## Examples

    ```elixir
    [orc_component, orc_component, wizard_component] = Ecspanse.Query.list_tagged_components_for_descendants(dungeon_entity, [:enemy])
    ```
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
  Returns a list of components tagged with a list of tags for the parents of a given entity.

  ## Examples

    ```elixir
    [hero_component] = Ecspanse.Query.list_tagged_components_for_parents(boots_entity, [:hero])
    ```
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
  Fetches the component by its module for a given entity.

  ## Examples

    ```elixir
    {:ok, gold_component} = Ecspanse.Query.fetch_component(hero_entity, Demo.Components.Gold)
    ```
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
  Fetches a tuple of components by their modules for a given entity.
  The entity must have all the components for the query to succeed.

  ## Examples

    ```elixir
    {:ok, {gold_component, gems_component}} = Ecspanse.Query.fetch_components(hero_entity, {Demo.Components.Gold, Demo.Components.Gems})
    ```
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
  Returns `true` if the entity has a component with the given module.

  ## Examples

    ```elixir
    true = Ecspanse.Query.has_component?(hero_entity, Demo.Components.Gold)
    ```
  """
  @doc group: :components
  @spec has_component?(Ecspanse.Entity.t(), module()) :: boolean()
  def has_component?(entity, component_module) when is_atom(component_module) do
    has_components?(entity, [component_module])
  end

  @doc """
  Returns `true` if the entity has all the components with the given modules.

  ## Examples

    ```elixir
    true = Ecspanse.Query.has_components?(hero_entity, [Demo.Components.Gold, Demo.Components.Gems])
    ```
  """
  @doc group: :components
  @spec has_components?(Ecspanse.Entity.t(), list(module())) :: boolean()
  def has_components?(entity, component_module_list)
      when is_list(component_module_list) do
    entities_components = Ecspanse.Util.list_entities_components()

    component_module_list -- Map.get(entities_components, entity.id, []) == []
  end

  @doc """
  Reurns `true` if a given entity is a child of another entity.
  ## Examples

    ```elixir
    true = Ecspanse.Query.is_child_of?(parent: hero_entity, child: boots_entity)
    ```
  """
  @doc group: :relationships
  @spec is_child_of?(parent: Ecspanse.Entity.t(), child: Ecspanse.Entity.t()) :: boolean()
  def is_child_of?(parent: %Entity{} = parent, child: %Entity{} = child) do
    parents = list_parents(child)
    parent in parents
  end

  @doc """
  Reurns `true` if a given entity is a parent of another entity.

  ## Examples

    ```elixir
    true = Ecspanse.Query.is_parent_of?(parent: hero_entity, child: boots_entity)
    ```
  """
  @doc group: :relationships
  @spec is_parent_of?(parent: Ecspanse.Entity.t(), child: Ecspanse.Entity.t()) :: boolean()
  def is_parent_of?(parent: %Entity{} = parent, child: %Entity{} = child) do
    children = list_children(parent)
    child in children
  end

  @doc """
  Returns true if the entity has at least a child with the given component module.

  ## Examples

    ```elixir
    true = Ecspanse.Query.has_children_with_component?(hero_entity, Demo.Components.Boots)
    ```
  """
  @doc group: :relationships
  @spec has_children_with_component?(Ecspanse.Entity.t(), module()) :: boolean()
  def has_children_with_component?(entity, component_module) do
    has_children_with_components?(entity, [component_module])
  end

  @doc """
  Returns true if the entity has at least a child with all the given component modules.

  ## Examples

    ```elixir
    true = Ecspanse.Query.has_children_with_components?(hero_entity, [Demo.Components.Boots, Demo.Components.Sword])
    ```
  """
  @doc group: :relationships
  @spec has_children_with_components?(Ecspanse.Entity.t(), list(module())) :: boolean()
  def has_children_with_components?(entity, component_module_list)
      when is_list(component_module_list) do
    memo_has_children_with_components?(entity, component_module_list)
  end

  @doc false
  defmemo memo_has_children_with_components?(entity, component_module_list),
    max_waiter: 1000,
    waiter_sleep_ms: 0 do
    components =
      select(List.to_tuple(component_module_list), for_children_of: [entity])
      |> stream()
      |> Enum.to_list()

    Enum.any?(components)
  end

  @doc """
  Returns true if the entity has at least a parent with the given component module.

  ## Examples

    ```elixir
    true = Ecspanse.Query.has_parents_with_component?(boots_entity, Demo.Components.Hero)
    ```
  """
  @doc group: :relationships
  @spec has_parents_with_component?(Ecspanse.Entity.t(), module()) ::
          boolean()
  def has_parents_with_component?(entity, component_module) do
    has_parents_with_components?(entity, [component_module])
  end

  @doc """
  Returns true if the entity has at least a parent with all the given component modules.

  ## Examples

    ```elixir
    true = Ecspanse.Query.has_parents_with_components?(boots_entity, [Demo.Components.Hero, Demo.Components.Gold])
    ```
  """
  @doc group: :relationships
  @spec has_parents_with_components?(Ecspanse.Entity.t(), list(module())) :: boolean()
  def has_parents_with_components?(entity, component_module_list)
      when is_list(component_module_list) do
    memo_has_parents_with_components?(entity, component_module_list)
  end

  @doc false
  defmemo memo_has_parents_with_components?(entity, component_module_list),
    max_waiter: 1000,
    waiter_sleep_ms: 0 do
    components =
      select(List.to_tuple(component_module_list), for_parents_of: [entity])
      |> stream()
      |> Enum.to_list()

    Enum.any?(components)
  end

  @doc """
  Fetches a resource by its module.

  ## Examples

    ```elixir
    {:ok, lobby_resource} = Ecspanse.Query.fetch_resource(Demo.Resources.Lobby)
    ```
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
        Keyword.get(filters, :for_descendants_of),
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
