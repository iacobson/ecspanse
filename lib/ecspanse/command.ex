defmodule Ecspanse.Command do
  @moduledoc """
  The `Ecspanse.Command` module provides a set of functions for managing entities, components and resources in the `Ecspanse` engine.

  Commands are the only way to change the state of components and resources in `Ecspanse`. These commands can only be run from systems, otherwise an error will be thrown.
  The `Ecspanse.Command` module includes functions for managing relationships between entities, such as adding and removing children and parents.
  All entity and component related commands can run for batches (lists) for performance reasons.

  All commands raise an error if the command fails.

  #### Entity Relationships

  The `Ecspanse.Command` module provides functions for managing relationships between entities.
  This is aslo a powerful tool to manage different kind of collections.

  > #### Ecspanse entities relationships are **bidirectional associations** {: .info}
  > When adding or removing children or parents, they are automatically added or removed from the corresponding parent or children entities.
  > The same applies when despawning entities.


  """

  require Logger
  require Ex2ms

  alias __MODULE__
  alias Ecspanse.Component
  alias Ecspanse.Entity
  alias Ecspanse.Query
  alias Ecspanse.Resource
  alias Ecspanse.Util

  defmodule Operation do
    @moduledoc false

    @type t :: %__MODULE__{
            name: name(),
            system: module(),
            entities_components:
              list(%{(entity_id :: binary()) => list(component_module :: module())}),
            system_execution: atom(),
            locked_components: list()
          }

    @type name ::
            :run
            | :spawn_entities
            | :despawn_entities
            | :despawn_entities_and_descendants
            | :add_components
            | :remove_components
            | :update_components
            | :add_children
            | :remove_children
            | :add_parents
            | :remove_parents
            | :insert_resource
            | :update_resource
            | :delete_resource

    defstruct name: nil,
              system: nil,
              entities_components: %{},
              system_execution: nil,
              locked_components: []
  end

  defmodule Error do
    @moduledoc false
    defexception [:message]

    @impl true
    def exception({%Ecspanse.Command.Operation{} = operation, message}) do
      msg = """
      System: #{Kernel.inspect(operation.system)}
      Operation: #{Kernel.inspect(operation.name)}
      Message: #{message}
      """

      %Error{message: msg}
    end
  end

  @typedoc false
  @type t :: %Command{
          return_result: any(),
          insert_components: list(component :: struct()),
          update_components: list(component :: struct()),
          delete_components: list(component :: struct())
        }

  defstruct return_result: nil,
            insert_components: [],
            update_components: [],
            delete_components: []

  @doc """
  Spawns a new entity with the given components and relations provided by the Ecspanse.Entity.entity_spec() type.
  When creating a new entity, at least one of the `components:`, `children:` or `parents:`
  must be provided in the entity spec, otherwise the entity cannot be persisted.

  Due to the potentially large number of components that may be affected by this operation,
  it is recommended to run this function in a synchronous system (such as a `frame_start` or `frame_end` system)
  to avoid the need to lock all involved components.

  ## Examples

    ```elixir
      %Ecspanse.Entity{} = Ecspanse.Command.spawn_entity!(
        {
          Ecspanse.Entity,
          id: "my_custom_id",
          components: [Demo.Components.Hero, {Demo.Components.Position, [x: 5, y: 3], [:hero, :map]}],
          children: [potion_entity, sword_entity],
          parents: [map_entity]
        }
      )
    ```
  """
  @doc group: :entities
  @spec spawn_entity!(Entity.entity_spec()) :: Entity.t()
  def spawn_entity!(spec) do
    [entity] = spawn_entities!([spec])
    entity
  end

  @doc """
  The same as `spawn_entity!/1` but spawns multiple entities at once.
  It takes a list of entity specs as argument and returns a list of Ecspanse.Entity structs.

  See `spawn_entity!/1` for more details.
  """
  @doc group: :entities
  @spec spawn_entities!(list(Entity.entity_spec())) :: list(Entity.t())
  def spawn_entities!([]), do: []

  def spawn_entities!(list) do
    operation = build_operation(:spawn_entities)
    command = apply_operation(operation, %Command{}, list)
    commit(command)
    command.return_result
  end

  @doc """
  Despawns the specified entity and removes all of its components.
  It also removes the despawned entity from its parent and child entities, if any.

  Due to the potentially large number of components that may be affected by this operation,
  it is recommended to run this function in a synchronous system (such as a `frame_start` or `frame_end` system)
  to avoid the need to lock all involved components.

  ## Examples

    ```elixir
    :ok = Ecspanse.Command.despawn_entity!(hero_entity)
    ```
  """
  @doc group: :entities
  @spec despawn_entity!(Entity.t()) :: :ok
  def despawn_entity!(entity) do
    despawn_entities!([entity])
  end

  @doc """
  The same as `despawn_entity!/1` but despawns multiple entities at once.
  It takes a list of entities as argument and returns `:ok`.  See `despawn_entity!/1` for more details.
  """
  @doc group: :entities
  @spec despawn_entities!(list(Entity.t())) :: :ok
  def despawn_entities!([]), do: :ok

  def despawn_entities!(list) do
    operation = build_operation(:despawn_entities)
    command = apply_operation(operation, %Command{}, list)
    commit(command)
    command.return_result
  end

  @doc """
  The same as `despawn_entity!/1` but recursively despawns also all descendant tree of the entity.

  This means that it will despawn the children of the entity, and their children, and so on.

  It is an efficient way to remove an entire entity tree with just one operation.
  Extra attention required for entities with shared children.

  See `despawn_entity!/1` for more details.
  """
  @doc group: :entities
  @spec despawn_entity_and_descendants!(Entity.t()) :: :ok
  def despawn_entity_and_descendants!(entity) do
    despawn_entities_and_descendants!([entity])
  end

  @doc """
  The same as `despawn_entity_and_descendants!/1` but despawns multiple entities and their descendants at once.
  It takes a list of entities as argument and returns `:ok`.
  """
  @doc group: :entities
  @spec despawn_entities_and_descendants!(list(Entity.t())) :: :ok
  def despawn_entities_and_descendants!([]), do: :ok

  def despawn_entities_and_descendants!(entities_list) do
    descendants_list = entities_descendants(entities_list)

    (entities_list ++ descendants_list)
    |> List.flatten()
    |> Enum.uniq()
    |> despawn_entities!()
  end

  @doc """
  Clones the specified entity and returns a new entity with the same components.

  Due to the potentially large number of components that may be affected by this operation,
  it is recommended to run this function in a synchronous system (such as a `frame_start` or `frame_end` system)
  to avoid the need to lock all involved components.

  > #### Note  {: .info}
  > The entity's `Ecspanse.Component.Children` and `Ecspanse.Component.Parents` components are not cloned.
  > Use `deep_clone_entity!/2` to clone the entity and all of its descendants.

  ## Options

  - `:id` - a custom unique ID for the entity (binary). If not provided, a random UUID will be generated.

  > #### Entity ID  {: .warning}
  > The entity IDs must be unique. Attention when providing the `:id` option.
  > If the provided ID is not unique, clonning the entity will raise an error.

  ## Examples

    ```elixir
    %Ecspanse.Entity{} = entity = Ecspanse.Command.clone_entity!(compass_entity)
    ```
  """
  @doc group: :entities
  @spec clone_entity!(Entity.t(), opts :: keyword()) :: Entity.t()
  def clone_entity!(entity, opts \\ []) do
    components = Ecspanse.Query.list_components(entity)

    component_specs =
      Enum.map(components, fn component ->
        state = component |> Map.from_struct() |> Map.delete(:__meta__) |> Map.to_list()
        {component.__struct__, state, Ecspanse.Query.list_tags(component)}
      end)

    case Keyword.fetch(opts, :id) do
      {:ok, entity_id} when is_binary(entity_id) ->
        spawn_entity!(
          {Ecspanse.Entity, id: entity_id, components: component_specs, children: [], parents: []}
        )

      _ ->
        spawn_entity!({Ecspanse.Entity, components: component_specs, children: [], parents: []})
    end
  end

  @doc """
  Clones the specified entity and all of its descendants and returns the newly cloned entity.

  Due to the potentially large number of components that may be affected by this operation,
  it is recommended to run this function in a synchronous system (such as a `frame_start` or `frame_end` system)
  to avoid the need to lock all involved components.

  ## Options

  - `:id` - a custom unique ID for the entity (binary). If not provided, a random UUID will be generated.

  > #### Entity ID  {: .warning}
  > The entity IDs must be unique. Attention when providing the `:id` option.
  > If the provided ID is not unique, clonning the entity will raise an error.

  The cloned descendants entities will receive a random UUID as ID by default.

  ## Cloning descendants

  The deep clonning operates only for the descendants of the entity.
  If any of the descendants has a parent that is not a descendant of the entity,
  the parent will not be cloned or referenced.

  If this is a desired behaviour, the parents should be added manually after the deep clonning.

  ## Examples

    ```elixir
    %Ecspanse.Entity{} = entity = Ecspanse.Command.deep_clone_entity!(enemy_entity)
    ```
  """
  @doc group: :entities
  @spec deep_clone_entity!(Entity.t(), opts: keyword()) :: Entity.t()
  def deep_clone_entity!(entity, opts \\ []) do
    cloned_entity = clone_entity!(entity, opts)
    children = Ecspanse.Query.list_children(entity)

    case children do
      [] ->
        cloned_entity

      children ->
        add_children!([{cloned_entity, Enum.map(children, &deep_clone_entity!/1)}])
        cloned_entity
    end
  end

  @doc """
  Adds a new component to the specified entity.

  > #### Info  {: .info}
  > An entity cannot have multiple components of the same type.
  > If an attempt is made to insert a component that already exists for the entity, an error will be raised.

  ## Examples

    ```elixir
    :ok = Ecspanse.Command.add_component!(hero_entity, Demo.Components.Gold)
    :ok = Ecspanse.Command.add_component!(hero_entity, {Demo.Components.Gold, [amount: 5], [:resource, :available]})
    ```
  """
  @doc group: :components
  @spec add_component!(Entity.t(), Component.component_spec()) :: :ok
  def add_component!(entity, component_spec) do
    add_components!([{entity, [component_spec]}])
  end

  @doc """
  The same as `add_component!/2` but adds multiple components to multiple entities at once.

  It takes a list of two element tuples as argument, where the first element of the tuple is the entity
  and the second element is a list of component specs.

  ## Examples
    ```elixir
    :ok = Ecspanse.Command.add_components!([
      {inventory_item_entity, [Demo.Components.Sword]},
      {hero_entity, [Demo.Components.Position, Demo.Components.Hero]}
    ])
    ```
  """
  @doc group: :components
  @spec add_components!(list({Entity.t(), list(Component.component_spec())})) :: :ok
  def add_components!([]), do: :ok

  def add_components!(list) do
    operation = build_operation(:add_components)
    command = apply_operation(operation, %Command{}, list)
    commit(command)
    command.return_result
  end

  @doc """
  Updates the state of an existing component.

  The function takes two arguments: the component struct to update and a keyword list of changes to apply.

  ## Examples

    ```elixir
    :ok = Ecspanse.Command.update_component!(position_component, x: :12)
    ```
  """
  @doc group: :components
  @spec update_component!(current_component :: struct(), state_changes :: keyword()) :: :ok
  def update_component!(component, changes_keyword) do
    update_components!([{component, changes_keyword}])
  end

  @doc """
  The same as `update_component!/2` but updates multiple components at once.

  It takes a list of two element tuples as argument, where the first element of the tuple is the component struct
  and the second element is a keyword list of changes to apply.

  ## Examples

    ```elixir
    :ok = Ecspanse.Command.update_components!([
      {position_component, x: 7, y: 9},
      {gold_component, amount: 12}
    ])
    ```
  """
  @doc group: :components
  @spec update_components!(list({current_component :: struct(), state_changes :: keyword()})) ::
          :ok
  def update_components!([]), do: :ok

  def update_components!(list) do
    operation = build_operation(:update_components)
    command = apply_operation(operation, %Command{}, list)
    commit(command)

    command.return_result
  end

  @doc """
  Removes an existing component from its entity. The components is destroyed.

  ## Examples

    ```elixir
    :ok = Ecspanse.Command.remove_component!(invisibility_component)
    ```
  """
  @doc group: :components
  @spec remove_component!(component :: struct()) :: :ok
  def remove_component!(component) do
    remove_components!([component])
  end

  @doc """
  The same as `remove_component!/1` but removes multiple components at once.
  """
  @doc group: :components
  @spec remove_components!(list(component :: struct())) :: :ok
  def remove_components!([]), do: :ok

  def remove_components!(components) do
    operation = build_operation(:remove_components)
    command = apply_operation(operation, %Command{}, components)
    commit(command)
    command.return_result
  end

  @doc """
  Adds an entity as child to a parent entity.

  ## Examples

    ```elixir
    :ok = Ecspanse.Command.add_child!(hero_entity, sword_entity)
    ```
  """
  @doc group: :relationships
  @spec add_child!(Entity.t(), child :: Entity.t()) :: :ok
  def add_child!(entity, child) do
    add_children!([{entity, [child]}])
  end

  @doc """
  The same as `add_child!/2` but can perform multiple operations at once.
  For example, adding multiple children to multiple parents.

  It takes a list of two element tuples as argument, where the first element of the tuple is the parent entity
  and the second element is a list of children entities.

  ## Examples

    ```elixir
    :ok = Ecspanse.Command.add_children!([
      {hero_entity, [sword_entity]},
      {market_entity, [map_entity, potion_entity]}
    ])
    ```
  """
  @doc group: :relationships
  @spec add_children!(list({Entity.t(), children :: list(Entity.t())})) :: :ok
  def add_children!([]), do: :ok

  def add_children!(list) do
    operation = build_operation(:add_children)
    command = apply_operation(operation, %Command{}, list)
    commit(command)
    command.return_result
  end

  @doc """
  Adds a parent entity to a child entity.

  ## Examples

    ```elixir
    :ok = Ecspanse.Command.add_parent!(sowrd_entity, hero_entity)
    ```
  """
  @doc group: :relationships
  @spec add_parent!(Entity.t(), parent :: Entity.t()) :: :ok
  def add_parent!(entity, parent) do
    add_parents!([{entity, [parent]}])
  end

  @doc """
  The same as `add_parent!/2` but can perform multiple operations at once.
  For example, adding multiple parents to multiple children.

  It takes a list of two element tuples as argument, where the first element of the tuple is the child entity
  and the second element is a list of parent entities.

  ## Examples

    ```elixir
    :ok = Ecspanse.Command.add_parents!([
      {sword_entity, [hero_entity]},
      {map_entity, [market_entity, vendor_entity]}
    ])
    ```
  """
  @doc group: :relationships
  @spec add_parents!(list({Entity.t(), parents :: list(Entity.t())})) :: :ok
  def add_parents!([]), do: :ok

  def add_parents!(list) do
    operation = build_operation(:add_parents)
    command = apply_operation(operation, %Command{}, list)
    commit(command)
    command.return_result
  end

  @doc """
  Removes a child entity from a parent entity.

  ## Examples

    ```elixir
    :ok = Ecspanse.Command.remove_child!(hero_entity, sword_entity)
    ```
  """
  @doc group: :relationships
  @spec remove_child!(Entity.t(), child :: Entity.t()) :: :ok
  def remove_child!(entity, child) do
    remove_children!([{entity, [child]}])
  end

  @doc """
  The same as `remove_child!/2` but can perform multiple operations at once.
  For example, removing multiple children from multiple parents.

  It takes a list of two element tuples as argument, where the first element of the tuple is the parent entity
  and the second element is a list of children entities.

  ## Examples

    ```elixir
    :ok = Ecspanse.Command.remove_children!([
      {hero_entity, [sword_entity]},
      {market_entity, [map_entity, potion_entity]}
    ])
    ```
  """
  @doc group: :relationships
  @spec remove_children!(list({Entity.t(), children :: list(Entity.t())})) :: :ok
  def remove_children!([]), do: :ok

  def remove_children!(list) do
    operation = build_operation(:remove_children)
    command = apply_operation(operation, %Command{}, list)
    commit(command)
    command.return_result
  end

  @doc """
  Removes a parent entity from a child entity.

  ## Examples

    ```elixir
    :ok = Ecspanse.Command.remove_parent!(sword_entity, hero_entity)
    ```
  """
  @doc group: :relationships
  @spec remove_parent!(Entity.t(), parent :: Entity.t()) :: :ok
  def remove_parent!(entity, parent) do
    remove_parents!([{entity, [parent]}])
  end

  @doc """
  The same as `remove_parent!/2` but can perform multiple operations at once.
  For example, removing multiple parents from multiple children.

  It takes a list of two element tuples as argument, where the first element of the tuple is the child entity
  and the second element is a list of parent entities.

  ## Examples

    ```elixir
    :ok = Ecspanse.Command.remove_parents!([
      {sword_entity, [hero_entity]},
      {map_entity, [market_entity, vendor_entity]}
    ])
    ```
  """
  @doc group: :relationships
  @spec remove_parents!(list({Entity.t(), parents :: list(Entity.t())})) :: :ok
  def remove_parents!([]), do: :ok

  def remove_parents!(list) do
    operation = build_operation(:remove_parents)
    command = apply_operation(operation, %Command{}, list)
    commit(command)
    command.return_result
  end

  @doc """
  Inserts a new global resource.

  > #### Info  {: .info}
  > An Ecspanse instance can only hold one resource of each type at a time.
  > If an attempt is made to insert a resource that already exists, an error will be raised.

  > #### Note  {: .warning}
  > Resources can be created, updated or deleted only from synchronous systems.

  ## Examples

    ```elixir
    :ok = Ecspanse.Command.insert_resource!({Demo.Resources.Lobby, player_count: 0})
    ```
  """
  @doc group: :resources
  @spec insert_resource!(resource_spec :: Resource.resource_spec()) :: resource :: struct()
  def insert_resource!(resource_spec) do
    operation = build_operation(:insert_resource)
    :ok = validate_payload(operation, resource_spec)
    command = apply_operation(operation, %Command{}, resource_spec)
    command.return_result
  end

  @doc """
  Updates an existing global resource.

  > #### Note  {: .warning}
  > Resources can be created, updated or deleted only from synchronous systems.

  ## Examples

    ```elixir
    :ok = Ecspanse.Command.update_resource!(lobby_resource, player_count: 1)
    ```
  """
  @doc group: :resources
  @spec update_resource!(resource :: struct(), state_changes :: keyword()) ::
          updated_resource :: struct()
  def update_resource!(resource, state_changes) do
    operation = build_operation(:update_resource)
    :ok = validate_payload(operation, {resource, state_changes})
    command = apply_operation(operation, %Command{}, {resource, state_changes})
    command.return_result
  end

  @doc """
  Deletes an existing global resource.

  > #### Note  {: .warning}
  > Resources can be created, updated or deleted only from synchronous systems.

  ## Examples

    ```elixir
    :ok = Ecspanse.Command.delete_resource!(lobby_resource)
    ```
  """
  @doc group: :resources
  @spec delete_resource!(resource :: struct()) :: deleted_resource :: struct()
  def delete_resource!(resource) do
    operation = build_operation(:delete_resource)
    :ok = validate_payload(operation, resource)
    command = apply_operation(operation, %Command{}, resource)
    command.return_result
  end

  ########

  defp build_operation(operation_name) do
    unless Process.get(:ecs_process_type) == :system do
      raise "Commands can only be executed from a System."
    end

    # Find the entities_components only once per Command and store it in the Operation
    entities_components = Util.list_entities_components()

    %Operation{
      name: operation_name,
      system: Process.get(:system_module),
      entities_components: entities_components,
      system_execution: Process.get(:system_execution),
      locked_components: Process.get(:locked_components)
    }
  end

  # resource payload validation

  defp validate_payload(%Operation{name: :insert_resource}, resource_module)
       when is_atom(resource_module),
       do: :ok

  defp validate_payload(%Operation{name: :insert_resource}, {resource_module, state})
       when is_atom(resource_module) and is_list(state),
       do: :ok

  defp validate_payload(%Operation{name: :insert_resource} = operation, value),
    do:
      raise(
        Error,
        {operation,
         "Expected  type `Ecspanse.Resource.resource_spec()` , got: `#{Kernel.inspect(value)}`"}
      )

  defp validate_payload(%Operation{name: :update_resource}, {resource, state_changes})
       when is_struct(resource) and is_list(state_changes),
       do: :ok

  defp validate_payload(%Operation{name: :update_resource} = operation, value),
    do:
      raise(
        Error,
        {operation,
         "Expected a resource state `struct()` and `keyword()` type args, got: `#{Kernel.inspect(value)}`"}
      )

  defp validate_payload(%Operation{name: :delete_resource}, resource)
       when is_struct(resource),
       do: :ok

  # Create, Update, Delete components

  # recieves [{Entity, opts}]
  defp apply_operation(
         %Operation{name: :spawn_entities} = operation,
         command,
         entity_spec_list
       ) do
    entity_spec_list =
      Enum.map(entity_spec_list, fn {_, opts} ->
        entity_id = Keyword.get(opts, :id, UUID.uuid4())
        component_specs = Keyword.get(opts, :components, [])

        component_modules =
          Enum.map(component_specs, fn
            module when is_atom(module) -> module
            {module, _} when is_atom(module) -> module
            {module, _, _} when is_atom(module) -> module
          end)

        # allow creation of entities only with empty children and parents
        children_entities = Keyword.get(opts, :children)
        parents_entities = Keyword.get(opts, :parents)

        :ok =
          validate_required_opts(operation, component_specs, children_entities, parents_entities)

        children_entities = Keyword.get(opts, :children, [])
        parents_entities = Keyword.get(opts, :parents, [])

        %{
          entity: Util.build_entity(entity_id),
          component_specs: component_specs,
          component_modules: component_modules ++ [Component.Children, Component.Parents],
          children_entities: children_entities,
          parents_entities: parents_entities
        }
      end)

    v1 =
      Task.async(fn ->
        entity_ids = Enum.map(entity_spec_list, fn %{entity: entity} -> entity.id end)
        :ok = validate_binary_entity_names(operation, entity_ids)
        :ok = validate_unique_entity_names(operation, entity_ids)
      end)

    v2 =
      Task.async(fn ->
        component_specs =
          Enum.map(entity_spec_list, fn %{component_specs: component_specs} -> component_specs end)
          |> List.flatten()

        :ok = validate_no_relation(operation, component_specs)
      end)

    v3 =
      Task.async(fn ->
        relation_entities =
          Enum.map(entity_spec_list, fn %{children_entities: children, parents_entities: parents} ->
            children ++ parents
          end)
          |> List.flatten()

        :ok = validate_entities(operation, relation_entities)
        :ok = validate_entities_exist(operation, relation_entities)
      end)

    custom_components =
      Task.async(fn ->
        for %{
              entity: entity,
              component_specs: component_specs
            } <- entity_spec_list do
          # Force the creation of the children and parents components on entity creation
          component_specs = component_specs ++ [Component.Children, Component.Parents]
          upsert_components(operation, entity, component_specs, [])
        end
      end)

    children_and_parents_components =
      Task.async(fn ->
        for %{
              entity: entity,
              children_entities: children_entities
            } <-
              entity_spec_list do
          create_children_and_parents(
            operation,
            entity,
            children_entities
          )
        end
      end)

    parents_and_children_components =
      Task.async(fn ->
        for %{
              entity: entity,
              parents_entities: parents_entities
            } <-
              entity_spec_list do
          create_parents_and_children(
            operation,
            entity,
            parents_entities
          )
        end
      end)

    Task.await_many([v1, v2, v3])

    components = Task.await(custom_components)

    ungrouped_relations =
      List.flatten(
        Task.await(children_and_parents_components) ++
          Task.await(parents_and_children_components)
      )

    relations = group_added_relations(operation, ungrouped_relations)

    # Relation components are always updated, not inserted

    %{
      command
      | return_result: Enum.map(entity_spec_list, fn %{entity: entity} -> entity end),
        insert_components: List.flatten(components),
        update_components: relations
    }
  end

  defp apply_operation(
         %Operation{name: :despawn_entities} = operation,
         command,
         entities
       ) do
    # Entity relations (children, parents) need to be handled before removing the entity's components

    :ok = validate_entities(operation, entities)
    table = Util.components_state_ets_table()

    children_and_parents_components =
      Task.async(fn ->
        for entity <- entities do
          # it is possible that the children component was already removed
          case :ets.lookup(table, {entity.id, Component.Children}) do
            [{{_id, Component.Children}, _, %Component.Children{entities: children_entities}}] ->
              remove_children_and_parents(operation, entity, children_entities)

            _ ->
              []
          end
        end
      end)

    parents_and_children_components =
      Task.async(fn ->
        for entity <- entities do
          case :ets.lookup(table, {entity.id, Component.Parents}) do
            [{{_id, Component.Parents}, _, %Component.Parents{entities: parents_entities}}] ->
              remove_parents_and_children(operation, entity, parents_entities)

            _ ->
              []
          end
        end
      end)

    deleted_components =
      for %Entity{id: id} <- entities do
        f =
          Ex2ms.fun do
            {{entity_id, _component_module}, _component_tags, component_state}
            when entity_id == ^id ->
              component_state
          end

        deleted_components_state = :ets.select(table, f)

        delete_components(operation, deleted_components_state)
      end

    # It is possible that more relations for the same entity are updated in the same command.
    # If there are more, they need to be grouped, leaving only the relations that are not deleted
    ungrouped_relations =
      List.flatten(
        Task.await(children_and_parents_components) ++ Task.await(parents_and_children_components)
      )

    relations = group_removed_relations(operation, ungrouped_relations)

    %{
      command
      | return_result: :ok,
        update_components: relations,
        delete_components: List.flatten(deleted_components)
    }
  end

  # receives a list of {%Entity{} = entity, component_specs}
  defp apply_operation(
         %Operation{name: :add_components} = operation,
         command,
         list
       ) do
    entities = Enum.map(list, fn {entity, _component_specs} -> entity end)

    v1 =
      Task.async(fn ->
        :ok = validate_entities(operation, entities)
        :ok = validate_entities_exist(operation, entities)
      end)

    v2 =
      Task.async(fn ->
        Enum.each(list, fn {entity, component_specs} ->
          :ok = validate_components_do_not_exist(operation, entity, component_specs)
        end)
      end)

    v3 =
      Task.async(fn ->
        component_specs =
          Enum.map(list, fn {_entity, component_specs} -> component_specs end)
          |> List.flatten()

        :ok = validate_no_relation(operation, component_specs)
      end)

    components =
      for {entity, component_specs} <- list do
        upsert_components(operation, entity, component_specs, [])
      end

    Task.await_many([v1, v2, v3])

    %{
      command
      | return_result: :ok,
        insert_components: List.flatten(components)
    }
  end

  # Receives a list of updates: [ {%Component{}, state_changes :: keyword()}]
  defp apply_operation(
         %Operation{name: :update_components} = operation,
         command,
         updates
       ) do
    v1 =
      Task.async(fn ->
        component_modules =
          Enum.map(updates, fn {component, _state_changes} -> component.__meta__.module end)

        :ok = validate_no_relation(operation, component_modules)
      end)

    v2 =
      Task.async(fn ->
        Enum.each(updates, fn {component, _state_changes} ->
          :ok = validate_is_component(operation, component.__meta__.module)
          :ok = validate_component_exists(operation, component)
        end)
      end)

    v3 =
      Task.async(fn ->
        Enum.each(updates, fn {component, _state_changes} ->
          :ok =
            validate_locked_component(
              operation,
              operation.system_execution,
              component.__meta__.module
            )
        end)
      end)

    components =
      for {component, state_changes} <- updates do
        state_changes = Keyword.delete(state_changes, :__meta__)
        new_component_state = struct(component, state_changes)
        :ok = validate_component_state(operation, new_component_state)

        {
          {component.__meta__.entity.id, component.__meta__.module},
          component.__meta__.tags,
          new_component_state
        }
      end

    Task.await_many([v1, v2, v3])

    %{
      command
      | return_result: :ok,
        update_components: components
    }
  end

  defp apply_operation(
         %Operation{name: :remove_components} = operation,
         command,
         components_state
       ) do
    :ok = validate_no_relation(operation, Enum.map(components_state, & &1.__meta__.module))

    deleted_components = delete_components(operation, components_state)

    %{
      command
      | return_result: :ok,
        delete_components: deleted_components
    }
  end

  # receives a list of [{%Entity{}, [%ChildrenEntity{}]}]
  defp apply_operation(
         %Operation{name: :add_children} = operation,
         command,
         list
       ) do
    v1 =
      Task.async(fn ->
        entities =
          Enum.map(list, fn {entity, children_entities} -> [entity | children_entities] end)
          |> List.flatten()

        :ok = validate_entities(operation, entities)
        :ok = validate_entities_exist(operation, entities)
      end)

    children_and_parents_components =
      for {entity, children_entities} <- list do
        create_children_and_parents(
          operation,
          entity,
          children_entities
        )
      end

    Task.await(v1)

    relations = group_added_relations(operation, List.flatten(children_and_parents_components))

    %{
      command
      | return_result: :ok,
        update_components: relations
    }
  end

  # receives a list of [{%Entity{}, [%ParentEntity{}]}]
  defp apply_operation(
         %Operation{name: :add_parents} = operation,
         command,
         list
       ) do
    v1 =
      Task.async(fn ->
        entities =
          Enum.map(list, fn {entity, parents_entities} -> [entity | parents_entities] end)
          |> List.flatten()

        :ok = validate_entities(operation, entities)
        :ok = validate_entities_exist(operation, entities)
      end)

    parents_and_children_components =
      for {entity, parents_entities} <- list do
        create_parents_and_children(
          operation,
          entity,
          parents_entities
        )
      end

    Task.await(v1)

    relations = group_added_relations(operation, List.flatten(parents_and_children_components))

    %{
      command
      | return_result: :ok,
        update_components: relations
    }
  end

  # receives a list of [{%Entity{}, [%ChildrenEntity{}]}]
  defp apply_operation(
         %Operation{name: :remove_children} = operation,
         command,
         list
       ) do
    v1 =
      Task.async(fn ->
        entities =
          Enum.map(list, fn {entity, children_entities} -> [entity | children_entities] end)
          |> List.flatten()

        :ok = validate_entities(operation, entities)
      end)

    v2 =
      Task.async(fn ->
        entities =
          Enum.map(list, fn {entity, _children_entities} -> entity end)
          |> List.flatten()

        # not checking if the children entities exist because they might have been deleted
        :ok = validate_entities_exist(operation, entities)
      end)

    children_and_parents_components =
      for {entity, children_entities} <- list do
        remove_children_and_parents(
          operation,
          entity,
          children_entities
        )
      end

    Task.await_many([v1, v2])
    relations = group_removed_relations(operation, List.flatten(children_and_parents_components))

    %{
      command
      | return_result: :ok,
        update_components: relations
    }
  end

  # receives a list of [{%Entity{}, [%ParentEntity{}]}]
  defp apply_operation(
         %Operation{name: :remove_parents} = operation,
         command,
         list
       ) do
    v1 =
      Task.async(fn ->
        entities =
          Enum.map(list, fn {entity, parents_entities} -> [entity | parents_entities] end)
          |> List.flatten()

        :ok = validate_entities(operation, entities)
      end)

    v2 =
      Task.async(fn ->
        entities =
          Enum.map(list, fn {entity, _parents_entities} -> entity end)
          |> List.flatten()

        # not checking if the parents entities exist because they might have been deleted
        :ok = validate_entities_exist(operation, entities)
      end)

    parents_and_children_components =
      for {entity, parents_entities} <- list do
        remove_parents_and_children(
          operation,
          entity,
          parents_entities
        )
      end

    Task.await_many([v1, v2])
    relations = group_removed_relations(operation, List.flatten(parents_and_children_components))

    %{
      command
      | return_result: :ok,
        update_components: relations
    }
  end

  defp apply_operation(%Operation{name: :insert_resource} = operation, command, resource_spec) do
    :ok = validate_resource_does_not_exist(operation, resource_spec)
    resource_state = upsert_resource(operation, resource_spec)

    %{
      command
      | return_result: resource_state
    }
  end

  defp apply_operation(
         %Operation{name: :update_resource} = operation,
         command,
         {resource_state, state_changes}
       ) do
    resource_module = resource_state.__meta__.module
    :ok = validate_resource_exists(operation, resource_state)

    state_changes = Keyword.delete(state_changes, :__meta__)

    state =
      resource_state
      |> Map.from_struct()
      |> Map.to_list()
      |> Keyword.merge(state_changes)

    resource_state = upsert_resource(operation, {resource_module, state})

    %{
      command
      | return_result: resource_state
    }
  end

  defp apply_operation(%Operation{name: :delete_resource} = operation, command, resource_state) do
    resource_module = resource_state.__meta__.module

    :ok =
      validate_locked_resource(
        operation,
        operation.system_execution,
        resource_module
      )

    table = Util.resources_state_ets_table()
    :ets.delete(table, resource_module)

    %{
      command
      | return_result: resource_state
    }
  end

  defp upsert_resource(operation, resource_module) when is_atom(resource_module) do
    upsert_resource(operation, {resource_module, []})
  end

  # composes the resource and inserts it into the ets table
  # the flow is different than the components, as the resources are managed one at a time
  defp upsert_resource(operation, {resource_module, state})
       when is_atom(resource_module) and is_list(state) do
    :ok = validate_is_resource(operation, resource_module)

    :ok =
      validate_locked_resource(
        operation,
        operation.system_execution,
        resource_module
      )

    resource_meta =
      struct!(Resource.Meta, %{
        module: resource_module
      })

    resource_state = struct!(resource_module, Keyword.put(state, :__meta__, resource_meta))
    :ok = validate_resource_state(operation, resource_state)
    # this is stored in the ETS table
    resource_with_key = {resource_module, resource_state}

    table = Util.resources_state_ets_table()

    :ets.insert(table, resource_with_key)

    resource_state
  end

  defp upsert_components(_operation, _entity, [], components), do: components

  defp upsert_components(
         operation,
         entity,
         [component_spec | component_specs],
         components
       ) do
    component = upsert_component(operation, entity, component_spec)
    upsert_components(operation, entity, component_specs, [component | components])
  end

  # Used also for children and parents. Validating children and parents should be done before this
  defp upsert_component(operation, entity, component_module)
       when is_atom(component_module) do
    upsert_component(operation, entity, {component_module, [], []})
  end

  defp upsert_component(operation, entity, {component_module, state}) do
    upsert_component(operation, entity, {component_module, state, []})
  end

  defp upsert_component(operation, entity, {component_module, state, component_spec_tags})
       when is_atom(component_module) and is_list(state) do
    :ok = validate_is_component(operation, component_module)
    :ok = validate_tags(operation, component_spec_tags)

    # VALIDATE THE COMPOENENT IS LOCKED FOR CREATION
    :ok =
      validate_locked_component(
        operation,
        operation.system_execution,
        component_module
      )

    component_tags_set = tags_set(component_module, component_spec_tags)

    component_meta =
      struct!(Component.Meta, %{
        entity: entity,
        module: component_module,
        tags: component_tags_set
      })

    component_state = struct!(component_module, Keyword.put(state, :__meta__, component_meta))
    :ok = validate_component_state(operation, component_state)
    # this is stored in the ETS table
    {{entity.id, component_module}, component_tags_set, component_state}
  end

  defp tags_set(component_module, []) do
    MapSet.new(component_module.__component_tags__())
  end

  defp tags_set(component_module, component_spec_tags) do
    # merging tags from compile time with tags from component spec
    MapSet.union(
      MapSet.new(component_module.__component_tags__()),
      MapSet.new(component_spec_tags)
    )
  end

  # there is no guarantee that the components belong to the same entity
  # returns a list of {{entity_id, component_module, tags}, component_state}
  defp delete_components(operation, components_state) do
    Enum.map(components_state, fn component_state ->
      entity = component_state.__meta__.entity
      component_module = component_state.__meta__.module
      component_tags = component_state.__meta__.tags

      :ok =
        validate_locked_component(
          operation,
          operation.system_execution,
          component_module
        )

      {{entity.id, component_module}, component_tags, component_state}
    end)
  end

  # Adds to, or creates the Entity's children and adds to or create the children's parents components
  defp create_children_and_parents(operation, entity, []) do
    # Create empty children component for entity
    empty_entity_children = upsert_children_for(operation, entity, [])
    [empty_entity_children]
  end

  defp create_children_and_parents(operation, entity, children)
       when is_list(children) do
    entity_children = upsert_children_for(operation, entity, children)

    entities_parents =
      Enum.map(children, fn child_entity ->
        upsert_parents_for(operation, child_entity, [entity])
      end)

    [entity_children | entities_parents]
  end

  # Adds to, or creates the Entity's parents and adds to or create the parent's children components
  defp create_parents_and_children(operation, entity, []) do
    # Create empty parents component for entity
    empty_entity_parents = upsert_parents_for(operation, entity, [])
    [empty_entity_parents]
  end

  defp create_parents_and_children(operation, entity, parents)
       when is_list(parents) do
    entity_parents = upsert_parents_for(operation, entity, parents)

    entities_children =
      Enum.map(parents, fn parent_entity ->
        upsert_children_for(operation, parent_entity, [
          entity
        ])
      end)

    [entity_parents | entities_children]
  end

  # Returns Children component with its key
  # {{entity_id, Component.Children}, MapSet.new(), %Component.Children{entities: [entity_3, entity_2, entity_1]}}
  # it is calling upsert_component which will validate the component is locked for creation
  defp upsert_children_for(operation, entity, children) do
    table = Util.components_state_ets_table()

    case :ets.lookup(table, {entity.id, Component.Children}) do
      [{_key, _tags, %Component.Children{entities: existing_children}}] ->
        children = Enum.concat(existing_children, children) |> Enum.uniq()

        upsert_component(
          operation,
          entity,
          {Component.Children, [entities: children]}
        )

      [] ->
        upsert_component(
          operation,
          entity,
          {Component.Children, [entities: children]}
        )
    end
  end

  # Returns a Parents component with its key
  # {{entity_id, Component.Parents}, MapSet.new(), %Component.Parents{entities: [entity_3, entity_2, entity_1]}}
  # it is calling upsert_component which will validate the component is locked for creation
  defp upsert_parents_for(operation, entity, parents) do
    table = Util.components_state_ets_table()

    case :ets.lookup(table, {entity.id, Component.Parents}) do
      [{_key, _tags, %Component.Parents{entities: existing_parents}}] ->
        parents = Enum.concat(existing_parents, parents) |> Enum.uniq()
        upsert_component(operation, entity, {Component.Parents, [entities: parents]})

      [] ->
        upsert_component(operation, entity, {Component.Parents, [entities: parents]})
    end
  end

  # Mark for update: Remove children entities from  target Entity
  # and parent entity from their parents
  defp remove_children_and_parents(_operation, _entity, []), do: []

  defp remove_children_and_parents(operation, entity, children) when is_list(children) do
    table = Util.components_state_ets_table()

    entity_children =
      case :ets.lookup(table, {entity.id, Component.Children}) do
        [{_key, _tags, %Component.Children{entities: existing_children}}] ->
          upsert_component(
            operation,
            entity,
            {Component.Children, [entities: existing_children -- children]}
          )

        [] ->
          nil
      end

    entities_parents =
      Enum.map(children, fn child_entity ->
        case :ets.lookup(table, {child_entity.id, Component.Parents}) do
          [{_key, _tags, %Component.Parents{entities: existing_parents}}] ->
            upsert_component(
              operation,
              child_entity,
              {Component.Parents, [entities: existing_parents -- [entity]]}
            )

          [] ->
            nil
        end
      end)

    [entity_children | entities_parents] |> Enum.reject(&is_nil/1)
  end

  # Mark for update: Remove parent entities from  target Entity
  # and children entity from their children
  defp remove_parents_and_children(_operation, _entity, []), do: []

  defp remove_parents_and_children(operation, entity, parents) do
    table = Util.components_state_ets_table()

    entity_parents =
      case :ets.lookup(table, {entity.id, Component.Parents}) do
        [{_key, _tags, %Component.Parents{entities: existing_parents}}] ->
          upsert_component(
            operation,
            entity,
            {Component.Parents, [entities: existing_parents -- parents]}
          )

        [] ->
          nil
      end

    entities_children =
      Enum.map(parents, fn parent_entity ->
        case :ets.lookup(table, {parent_entity.id, Component.Children}) do
          [{_key, _tags, %Component.Children{entities: existing_children}}] ->
            upsert_component(
              operation,
              parent_entity,
              {Component.Children, [entities: existing_children -- [entity]]}
            )

          [] ->
            nil
        end
      end)

    [entity_parents | entities_children] |> Enum.reject(&is_nil/1)
  end

  # Grouping relations

  # It is possible that more relations for the same entity are updated in the same command.
  # If there are more, they need to be grouped
  defp group_added_relations(operation, relations) do
    relations
    |> Enum.group_by(fn {k, _tags, _v} -> k end, fn {_k, _tags, v} -> v end)
    |> Enum.map(fn
      {k, [v]} ->
        {k, MapSet.new(), v}

      {{entity_id, module}, values} ->
        list = Enum.map(values, fn value -> value.entities end) |> List.flatten() |> Enum.uniq()
        entity = Util.build_entity(entity_id)

        upsert_component(operation, entity, {module, entities: list})
    end)
  end

  defp group_removed_relations(operation, relations) do
    relations
    |> Enum.group_by(fn {k, _tags, _v} -> k end, fn {_k, _tags, v} -> v end)
    |> Enum.map(fn
      {k, [v]} ->
        {k, MapSet.new(), v}

      {{entity_id, module}, values} ->
        list =
          Enum.map(values, fn value -> value.entities end)
          |> List.flatten()
          |> Enum.uniq()
          |> select_entities_present_in_all_relations(values)

        entity = Util.build_entity(entity_id)

        upsert_component(operation, entity, {module, entities: list})
    end)
  end

  defp select_entities_present_in_all_relations(entity_list, relations) do
    Enum.filter(
      entity_list,
      fn entity ->
        Enum.all?(
          relations,
          fn r -> entity in r.entities end
        )
      end
    )
  end

  # Component CRUD Validations

  defp validate_required_opts(operation, [], nil, nil) do
    raise Error,
          {operation,
           "Expected at least one of the following options in the entity_spec when creating an entity: `components`, `children`, `parents`"}
  end

  defp validate_required_opts(_operation, _, _, _), do: :ok

  defp validate_entities(operation, entities) do
    non_enitites = Enum.reject(entities, &match?(%Entity{}, &1))

    case non_enitites do
      [] ->
        :ok

      _ ->
        raise Error,
              {operation,
               "Expected a list of `Ecspanse.Entity.t()` types, got: `#{Kernel.inspect(non_enitites)}`"}
    end
  end

  defp validate_binary_entity_names(operation, entity_ids) do
    Enum.each(entity_ids, fn entity_id ->
      case is_binary(entity_id) do
        true ->
          :ok

        false ->
          raise Error,
                {operation,
                 "Entity id `#{entity_id}` must be a binary. Entity ids must be unique."}
      end
    end)

    :ok
  end

  defp validate_unique_entity_names(operation, entity_ids) do
    table = Util.components_state_ets_table()

    Enum.each(entity_ids, fn entity_id ->
      f =
        Ex2ms.fun do
          {{^entity_id, _component_module}, _component_tags, _component_state} -> ^entity_id
        end

      result = :ets.select(table, f, 1)

      case result do
        {[], _} ->
          :ok

        {nil, _} ->
          :ok

        :"$end_of_table" ->
          :ok

        _ ->
          raise Error,
                {operation, "Entity id `#{entity_id}` already exists. Entity ids must be unique."}
      end
    end)

    :ok
  end

  defp validate_entities_exist(_operation, []), do: :ok

  defp validate_entities_exist(operation, entities) do
    table = Util.components_state_ets_table()
    entity_ids = Enum.map(entities, & &1.id)

    # All this, just because `when entity_id in ^entity_ids` doesn't work :(

    result =
      entity_ids
      |> Stream.map(fn target_entity_id ->
        f =
          Ex2ms.fun do
            {{entity_id, _component_module}, _tags, _component_state}
            when entity_id == ^target_entity_id ->
              entity_id
          end

        # limit to 1. We don't care about the result, just if it exists
        :ets.select(table, f, 1)
      end)
      |> Stream.map(fn
        {id_list, _} -> id_list
        :"$end_of_table" -> []
      end)
      |> Enum.concat()

    case entity_ids -- result do
      [] ->
        :ok

      {nil, _} ->
        :ok

      :"$end_of_table" ->
        :ok

      missing_entity_ids ->
        raise Error,
              {operation, "Entity ids `#{Kernel.inspect(missing_entity_ids)}` do not exist."}
    end
  end

  defp validate_is_component(operation, component_module) do
    Util.validate_ecs_type(
      component_module,
      :component,
      Error,
      {operation, "#{Kernel.inspect(component_module)} is not a Component"}
    )
  end

  defp validate_no_relation(operation, component_specs) do
    component_modules =
      Enum.map(component_specs, fn
        {component_module, _, _} when is_atom(component_module) -> component_module
        {component_module, _} when is_atom(component_module) -> component_module
        component_module when is_atom(component_module) -> component_module
      end)

    if component_modules -- [Component.Children, Component.Parent] == component_modules do
      :ok
    else
      raise Error,
            {operation,
             "Children or Parent relation not expected. Use the the dedicated `children` and `parents` options when creating a new entity. Or use the dedicated `add_child/3` and `add_parent/3` commands."}
    end
  end

  defp validate_component_state(operation, component_state_struct) do
    if function_exported?(component_state_struct.__meta__.module, :validate, 1) do
      case component_state_struct.__meta__.module.validate(component_state_struct) do
        :ok ->
          :ok

        {:error, error} ->
          raise Error,
                {operation,
                 "#{Kernel.inspect(component_state_struct)} state is invalid. Error: #{Kernel.inspect(error)}"}
      end
    else
      :ok
    end
  end

  # There is no lock validation for sync systems
  defp validate_locked_component(operation, :sync, component_module) do
    unless Enum.empty?(operation.locked_components) do
      Logger.warning(
        "#{Kernel.inspect(operation)}. Component: #{Kernel.inspect(component_module)}. There is no need to lock components in Systems that execute synchronously. The values are ignored"
      )
    end

    :ok
  end

  defp validate_locked_component(operation, :async, component_module) do
    locked_components = operation.locked_components

    if component_module in locked_components do
      :ok
    else
      raise Error,
            {operation,
             "#{Kernel.inspect(component_module)} is not locked. It can not be created or updated in an async System"}
    end
  end

  defp validate_components_do_not_exist(operation, %Entity{id: entity_id}, component_specs) do
    entities_components = operation.entities_components

    case entities_components[entity_id] do
      nil ->
        :ok

      [] ->
        :ok

      existing_components when is_list(existing_components) ->
        component_modules =
          Enum.map(component_specs, fn
            {component_module, _, _} when is_atom(component_module) -> component_module
            {component_module, _} when is_atom(component_module) -> component_module
            component_module when is_atom(component_module) -> component_module
          end)

        if component_modules -- existing_components == component_modules do
          :ok
        else
          duplicates = component_modules -- component_modules -- existing_components

          raise Error,
                {operation,
                 "Components #{Kernel.inspect(duplicates)} already exist for the entity #{Kernel.inspect(entity_id)}"}
        end
    end
  end

  defp validate_component_exists(operation, component) do
    table = Util.components_state_ets_table()

    case :ets.lookup(
           table,
           {component.__meta__.entity.id, component.__meta__.module}
         ) do
      [{_key, _tags, _val}] -> :ok
      _ -> raise Error, {operation, "#{Kernel.inspect(component)} does not exist"}
    end
  end

  # Resources CRUD validations

  defp validate_is_resource(operation, {resource_module, _state}) do
    validate_is_resource(operation, resource_module)
  end

  defp validate_is_resource(operation, resource_module) do
    Util.validate_ecs_type(
      resource_module,
      :resource,
      Error,
      {operation, "#{Kernel.inspect(resource_module)} is not a Resource"}
    )
  end

  defp validate_resource_state(operation, resource_state_struct) do
    if function_exported?(resource_state_struct.__meta__.module, :validate, 1) do
      case resource_state_struct.__meta__.module.validate(resource_state_struct) do
        :ok ->
          :ok

        {:error, error} ->
          raise Error,
                {operation,
                 "#{Kernel.inspect(resource_state_struct)} state is invalid. Error: #{Kernel.inspect(error)}"}
      end
    else
      :ok
    end
  end

  # for now Resources CRUD are supported only in sync Systems!
  defp validate_locked_resource(_operation, :sync, _resource_module) do
    :ok
  end

  defp validate_locked_resource(operation, :async, resource_module) do
    raise Error,
          {operation,
           "Resource commands are supported only in sync Systems (startup_systems, frame_start_system, frame_end_system). Resource: #{Kernel.inspect(resource_module)} "}
  end

  defp validate_resource_does_not_exist(operation, resource_spec) do
    resource_module =
      case resource_spec do
        {resource_module, _} when is_atom(resource_module) -> resource_module
        resource_module when is_atom(resource_module) -> resource_module
      end

    table = Util.resources_state_ets_table()

    case :ets.lookup(table, resource_module) do
      [] ->
        :ok

      _ ->
        raise Error,
              {operation, "Resource #{Kernel.inspect(resource_module)} already exists"}
    end
  end

  defp validate_resource_exists(operation, resource) do
    table = Util.resources_state_ets_table()

    case :ets.lookup(table, resource.__meta__.module) do
      [{_key, _val}] -> :ok
      _ -> raise Error, {operation, "#{Kernel.inspect(resource)} does not exist"}
    end
  end

  defp validate_tags(operation, tags) when is_list(tags) do
    non_tags = Enum.reject(tags, &is_atom/1)

    case non_tags do
      [] ->
        :ok

      _ ->
        raise Error,
              {operation, "Expected tags to be a list of atoms, got: #{Kernel.inspect(non_tags)}"}
    end
  end

  defp validate_tags(operation, tags) do
    raise Error, {operation, "Expected tags to be a list of atoms, got: #{Kernel.inspect(tags)}"}
  end

  # Commits

  # CRUD operations are handled as a bundle for each command
  defp commit(%Command{} = command) do
    :ok = commit_inserts(command.insert_components)
    :ok = commit_updates(command.update_components)
    :ok = commit_deletes(command.delete_components)
  end

  defp commit_inserts([]), do: :ok

  defp commit_inserts(components) do
    table = Util.components_state_ets_table()

    # do not allow multiple operations for the same component
    unique_components = Enum.uniq_by(components, fn {key, _tags, _val} -> key end)

    duplicates = components -- unique_components

    case duplicates do
      [] ->
        :ets.insert(table, components)

        invalidate_cache_on_create_and_delete(components)

        :ok

      _ ->
        raise "Error inserting components. Duplicate components insert is not allowed in the same Command: #{Kernel.inspect(duplicates)}"
    end
  end

  defp commit_updates([]), do: :ok

  defp commit_updates(components) do
    table = Util.components_state_ets_table()

    # do not allow multiple operations for the same component
    unique_components = Enum.uniq_by(components, fn {key, _tags, _val} -> key end)

    duplicates = components -- unique_components

    case duplicates do
      [] ->
        :ets.insert(table, components)

        invalidate =
          Task.async(fn ->
            maybe_invalidate_cache_on_relation_update(components)
          end)

        Task.await(invalidate)
        :ok

      _ ->
        raise "Error updating components. Duplicate components update is not allowed in the same Command: #{Kernel.inspect(duplicates)}"
    end
  end

  defp commit_deletes([]), do: :ok

  defp commit_deletes(components) do
    table = Util.components_state_ets_table()

    Enum.each(components, fn {key, _tags, _val} ->
      :ets.delete(table, key)
    end)

    invalidate_cache_on_create_and_delete(components)

    :ok
  end

  defp maybe_invalidate_cache_on_relation_update(components) do
    relation_updates =
      Enum.any?(components, fn {{_entity_id, module}, _tags, _component} ->
        module in [Ecspanse.Component.Children, Ecspanse.Component.Parents]
      end)

    if relation_updates do
      # invalidate the cache when updating Children or Parents
      Util.invalidate_query_cache()
    end
  end

  defp invalidate_cache_on_create_and_delete(components) do
    i1 =
      Task.async(fn ->
        Util.invalidate_cache()
      end)

    i2 =
      Task.async(fn ->
        maybe_invalidate_tags_cache(components)
      end)

    i3 =
      Task.async(fn ->
        maybe_invalidate_timer_tag_cache(components)
      end)

    Task.await_many([i1, i2, i3])
  end

  defp maybe_invalidate_tags_cache(components) do
    components_with_tags =
      Enum.any?(components, fn {{_entity_id, _module}, tags, _component} -> Enum.any?(tags) end)

    if components_with_tags do
      Util.invalidate_tags_cache()
    end
  end

  defp maybe_invalidate_timer_tag_cache(components) do
    timer_component_tag = Ecspanse.Template.Component.Timer.timer_component_tag()

    components_with_timer_tag =
      Enum.any?(components, fn {{_entity_id, _module}, tags, _component} ->
        timer_component_tag in tags
      end)

    if components_with_timer_tag do
      Util.invalidate_timer_tag_cache()
    end
  end

  # helper query functions

  defp entities_descendants(entities) do
    Query.select({Ecspanse.Entity}, for_descendants_of: entities)
    |> Query.stream()
    |> Stream.map(fn {entity} -> entity end)
    |> Enum.to_list()
  end
end
