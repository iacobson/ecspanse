defmodule Ecspanse.Command do
  @moduledoc """
  TODO

  An entity children and parents will be unique. If the same entity is added twice, it will be ignored.

  When adding or removing children or parents, they are automatically added or removed also
  from the corresponding parent or children entities.
  The same when despawning entities.


  For performance reasons all Entity and Component related commands run for batches (lists)
  """

  require Logger
  require Ex2ms

  alias __MODULE__
  alias Ecspanse.Component
  alias Ecspanse.Entity
  alias Ecspanse.Event
  alias Ecspanse.Query
  alias Ecspanse.Resource

  defmodule Operation do
    @moduledoc false

    @type t :: %__MODULE__{
            name: name(),
            system: module(),
            token: binary(),
            entities_components:
              list(%{(entity_id :: binary()) => list(component_module :: module())}),
            components_state_ets_name: binary(),
            resources_state_ets_name: binary(),
            events_ets_name: binary(),
            system_execution: atom(),
            locked_components: list()
          }

    @type name ::
            :run
            | :spawn_entities
            | :despawn_entities
            | :despawn_entities_and_children
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
              token: nil,
              entities_components: %{},
              components_state_ets_name: nil,
              resources_state_ets_name: nil,
              events_ets_name: nil,
              system_execution: nil,
              locked_components: []
  end

  defmodule Error do
    @moduledoc false
    defexception [:message]

    @impl true
    def exception({%Ecspanse.Command.Operation{} = operation, message}) do
      msg = """
      System: #{inspect(operation.system)}
      Operation: #{inspect(operation.name)}
      Message: #{message}
      """

      %Error{message: msg}
    end
  end

  @type t :: %Command{
          return_result: any(),
          insert_components: list(Component.t()),
          update_components: list(Component.t()),
          delete_components: list(Component.t())
        }

  defstruct return_result: nil,
            insert_components: [],
            update_components: [],
            delete_components: []

  @doc """
  TODO
  """
  @spec spawn_entity!(Entity.entity_spec()) :: Entity.t()
  def spawn_entity!(spec) do
    [entity] = spawn_entities!([spec])
    entity
  end

  @doc """
  TODO
  """
  @spec spawn_entities!(list(Entity.entity_spec())) :: list(Entity.t())
  def spawn_entities!([]), do: []

  def spawn_entities!(list) do
    operation = build_operation(:spawn_entities)
    command = apply_operation(operation, %Command{}, list)
    commit(command)
    command.return_result
  end

  @doc """
  TODO
  """
  @spec despawn_entity!(Entity.t()) :: :ok
  def despawn_entity!(entity) do
    despawn_entities!([entity])
  end

  @doc """
  TODO
  Removes the entity and all its components.
      # when removing an entity, remove it from its parents and children


  TIP: due to many components that are affected, it may make sense to run this
  in a sync system (frame_start or frame_end system) to avoid the need to lock all involved components
  """
  @spec despawn_entities!(list(Entity.t())) :: :ok
  def despawn_entities!([]), do: :ok

  def despawn_entities!(list) do
    operation = build_operation(:despawn_entities)
    command = apply_operation(operation, %Command{}, list)
    commit(command)
    command.return_result
  end

  @doc """
  TODO
  """
  @spec despawn_entity_and_children!(Entity.t()) :: :ok
  def despawn_entity_and_children!(entity) do
    despawn_entities_and_children!([entity])
  end

  @doc """
  The same as `despawn_entities!/1` but recursively despawns also all children of the entities.
  Meaning it will despawn the children and theri children and so on.
  """
  @spec despawn_entities_and_children!(list(Entity.t())) :: :ok
  def despawn_entities_and_children!([]), do: :ok

  def despawn_entities_and_children!(entities_list) do
    operation = build_operation(:despawn_entities_and_children)
    recursive_children_list = recursive_children_entities(operation, entities_list, [])

    (entities_list ++ recursive_children_list)
    |> List.flatten()
    |> Enum.uniq()
    |> despawn_entities!()
  end

  @doc """
  # TODO
  """
  @spec add_component!(Entity.t(), Component.component_spec()) :: :ok
  def add_component!(entity, component_spec) do
    add_components!([{entity, [component_spec]}])
  end

  @doc """
  # TODO
  An entity can have only one component of a given type.
  Inserting components of a type that already exists will raise an error.
  """
  @spec add_components!(list({Entity.t(), list(Component.component_spec())})) :: :ok
  def add_components!([]), do: :ok

  def add_components!(list) do
    operation = build_operation(:add_components)
    command = apply_operation(operation, %Command{}, list)
    commit(command)
    command.return_result
  end

  @doc """
  TODO
  """
  @spec update_component!(current_component :: struct(), state_changes :: keyword()) :: :ok
  def update_component!(component, changes_keyword) do
    update_components!([{component, changes_keyword}])
  end

  @doc """
  TODO
  """
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
  TODO
  """
  @spec remove_component!(component :: struct()) :: :ok
  def remove_component!(component) do
    remove_components!([component])
  end

  @doc """
  TODO
  """
  @spec remove_components!(list(component :: struct())) :: :ok
  def remove_components!([]), do: :ok

  def remove_components!(components) do
    operation = build_operation(:remove_components)
    command = apply_operation(operation, %Command{}, components)
    commit(command)
    command.return_result
  end

  @doc """
  TODO
  """
  @spec add_child!(Entity.t(), child :: Entity.t()) :: :ok
  def add_child!(entity, child) do
    add_children!([{entity, [child]}])
  end

  @doc """
  TODO
  """
  @spec add_children!(list({Entity.t(), children :: list(Entity.t())})) :: :ok
  def add_children!([]), do: :ok

  def add_children!(list) do
    operation = build_operation(:add_children)
    command = apply_operation(operation, %Command{}, list)
    commit(command)
    command.return_result
  end

  @doc """
  TODO
  """
  @spec add_parent!(Entity.t(), parent :: Entity.t()) :: :ok
  def add_parent!(entity, parent) do
    add_parents!([{entity, [parent]}])
  end

  @doc """
  TODO
  """
  @spec add_parents!(list({Entity.t(), parents :: list(Entity.t())})) :: :ok
  def add_parents!([]), do: :ok

  def add_parents!(list) do
    operation = build_operation(:add_parents)
    command = apply_operation(operation, %Command{}, list)
    commit(command)
    command.return_result
  end

  @doc """
  TODO
  """
  @spec remove_child!(Entity.t(), child :: Entity.t()) :: :ok
  def remove_child!(entity, child) do
    remove_children!([{entity, [child]}])
  end

  @doc """
  TODO
  """
  @spec remove_children!(list({Entity.t(), children :: list(Entity.t())})) :: :ok
  def remove_children!([]), do: :ok

  def remove_children!(list) do
    operation = build_operation(:remove_children)
    command = apply_operation(operation, %Command{}, list)
    commit(command)
    command.return_result
  end

  @doc """
  TODO
  """
  @spec remove_parent!(Entity.t(), parent :: Entity.t()) :: :ok
  def remove_parent!(entity, parent) do
    remove_parents!([{entity, [parent]}])
  end

  @doc """
  TODO
  """
  @spec remove_parents!(list({Entity.t(), parents :: list(Entity.t())})) :: :ok
  def remove_parents!([]), do: :ok

  def remove_parents!(list) do
    operation = build_operation(:remove_parents)
    command = apply_operation(operation, %Command{}, list)
    commit(command)
    command.return_result
  end

  @doc """
  TODO
  """
  @spec insert_resource!(resource_spec :: Resource.resource_spec()) :: resource :: struct()
  def insert_resource!(resource_spec) do
    operation = build_operation(:insert_resource)
    :ok = validate_payload(operation, resource_spec)
    command = apply_operation(operation, %Command{}, resource_spec)
    command.return_result
  end

  @doc """
  TODO
  """
  @spec update_resource!({resource :: struct(), state_changes :: keyword()}) ::
          updated_resource :: struct()
  def update_resource!({resource, state_changes}) do
    operation = build_operation(:update_resource)
    :ok = validate_payload(operation, {resource, state_changes})
    command = apply_operation(operation, %Command{}, {resource, state_changes})
    command.return_result
  end

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
    components_state_ets_name = Process.get(:components_state_ets_name)

    entities_components = Ecspanse.Util.list_entities_components(components_state_ets_name)

    %Operation{
      name: operation_name,
      system: Process.get(:system_module),
      token: Process.get(:token),
      entities_components: entities_components,
      components_state_ets_name: components_state_ets_name,
      resources_state_ets_name: Process.get(:resources_state_ets_name),
      events_ets_name: Process.get(:events_ets_name),
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
         "Expected  type `Ecspanse.Resource.resource_spec()` , got: `#{inspect(value)}`"}
      )

  defp validate_payload(%Operation{name: :update_resource}, {resource, state_changes})
       when is_struct(resource) and is_list(state_changes),
       do: :ok

  defp validate_payload(%Operation{name: :update_resource} = operation, value),
    do:
      raise(
        Error,
        {operation,
         "Expected a resource state `struct()` and `keyword()` type args, got: `#{inspect(value)}`"}
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
        entity_id = Keyword.get(opts, :name, UUID.uuid4())
        component_specs = Keyword.get(opts, :components, [])

        component_modules =
          Enum.map(component_specs, fn
            module when is_atom(module) -> module
            {module, _} when is_atom(module) -> module
          end)

        entity_type_component_module =
          get_entity_type_component_module_form_component_specs(operation, component_specs)

        children_entities = Keyword.get(opts, :children, [])
        parents_entities = Keyword.get(opts, :parents, [])

        %{
          entity: Entity.build(entity_id),
          component_specs: component_specs,
          component_modules: component_modules ++ [Component.Children, Component.Parents],
          entity_type_component_module: entity_type_component_module,
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
              entity_type_component_module: entity_type_component_module,
              component_specs: component_specs
            } <- entity_spec_list do
          upsert_components(operation, entity, entity_type_component_module, component_specs, [])
        end
      end)

    children_and_parents_components =
      Task.async(fn ->
        for %{
              entity: entity,
              entity_type_component_module: entity_type_component_module,
              children_entities: children_entities
            } <-
              entity_spec_list do
          create_children_and_parents(
            operation,
            entity,
            entity_type_component_module,
            children_entities
          )
        end
      end)

    parents_and_children_components =
      Task.async(fn ->
        for %{
              entity: entity,
              entity_type_component_module: entity_type_component_module,
              parents_entities: parents_entities
            } <-
              entity_spec_list do
          create_parents_and_children(
            operation,
            entity,
            entity_type_component_module,
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
    table = operation.components_state_ets_name

    children_and_parents_components =
      Task.async(fn ->
        for entity <- entities do
          # it is possible that the children component was already removed
          case :ets.lookup(table, {entity.id, Component.Children, []}) do
            [{{_id, Component.Children, []}, %Component.Children{list: children_entities}}] ->
              remove_children_and_parents(operation, entity, children_entities)

            _ ->
              []
          end
        end
      end)

    parents_and_children_components =
      Task.async(fn ->
        for entity <- entities do
          case :ets.lookup(table, {entity.id, Component.Parents, []}) do
            [{{_id, Component.Parents, []}, %Component.Parents{list: parents_entities}}] ->
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
            {{entity_id, _component_module, _component_groups}, component_state}
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
        entity_type_component_module =
          get_entity_type_component_module_form_component_specs(operation, component_specs) ||
            get_entity_type_component_module_for_entity(operation, entity)

        upsert_components(operation, entity, entity_type_component_module, component_specs, [])
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
          :ok = validate_component_writable(operation, component)
        end)
      end)

    v3 =
      Task.async(fn ->
        Enum.each(updates, fn {component, _state_changes} ->
          entity_type_component_module =
            get_entity_type_component_module_for_entity(operation, component.__meta__.entity)

          :ok =
            validate_locked_component(
              operation,
              operation.system_execution,
              component.__meta__.module,
              entity_type_component_module
            )
        end)
      end)

    components =
      for {component, state_changes} <- updates do
        state_changes = Keyword.delete(state_changes, :__meta__)
        new_component_state = struct(component, state_changes)
        :ok = validate_component_state(operation, new_component_state)

        {{component.__meta__.entity.id, component.__meta__.module, component.__meta__.groups},
         new_component_state}
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
        entity_type_component_module =
          get_entity_type_component_module_for_entity(operation, entity)

        create_children_and_parents(
          operation,
          entity,
          entity_type_component_module,
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
        entity_type_component_module =
          get_entity_type_component_module_for_entity(operation, entity)

        create_parents_and_children(
          operation,
          entity,
          entity_type_component_module,
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

    resource_created_event(resource_state)

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
    :ok = validate_resource_writable(operation, resource_state)

    state_changes = Keyword.delete(state_changes, :__meta__)

    state =
      resource_state
      |> Map.from_struct()
      |> Map.to_list()
      |> Keyword.merge(state_changes)

    resource_state = upsert_resource(operation, {resource_module, state})

    resource_updated_event(resource_state)

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

    table = operation.resources_state_ets_name
    :ets.delete(table, resource_module)
    resource_deleted_event(resource_state)

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
        module: resource_module,
        access_mode: resource_module.__resource_access_mode__()
      })

    resource_state = struct!(resource_module, Keyword.put(state, :__meta__, resource_meta))
    :ok = validate_resource_state(operation, resource_state)
    # this is stored in the ETS table
    resource_with_key = {resource_module, resource_state}

    table = operation.resources_state_ets_name

    :ets.insert(table, resource_with_key)

    resource_state
  end

  defp upsert_components(_operation, _entity, _entity_type, [], components), do: components

  defp upsert_components(
         operation,
         entity,
         entity_type,
         [component_spec | component_specs],
         components
       ) do
    component = upsert_component(operation, entity, component_spec, entity_type)
    upsert_components(operation, entity, entity_type, component_specs, [component | components])
  end

  # Used also for children and parents. Validating children and parents should be done before this
  defp upsert_component(operation, entity, component_module, entity_type)
       when is_atom(component_module) do
    upsert_component(operation, entity, {component_module, []}, entity_type)
  end

  defp upsert_component(operation, entity, {component_module, state}, entity_type)
       when is_atom(component_module) and is_list(state) do
    :ok = validate_is_component(operation, component_module)

    # VALIDATE THE COMPOENENT IS LOCKED FOR CREATION
    :ok =
      validate_locked_component(
        operation,
        operation.system_execution,
        component_module,
        entity_type
      )

    :ok = validate_entity_type_component(operation, component_module, entity_type)

    component_meta =
      struct!(Component.Meta, %{
        entity: entity,
        module: component_module,
        access_mode: component_module.__component_access_mode__(),
        groups: component_module.__component_groups__()
      })

    component_state = struct!(component_module, Keyword.put(state, :__meta__, component_meta))
    :ok = validate_component_state(operation, component_state)
    # this is stored in the ETS table
    {{entity.id, component_module, component_module.__component_groups__()}, component_state}
  end

  # there is no guarantee that the components belong to the same entity
  # returns a list of {{entity_id, component_module, groups}, component_state}
  defp delete_components(operation, components_state) do
    Enum.map(components_state, fn component_state ->
      entity = component_state.__meta__.entity
      component_module = component_state.__meta__.module
      component_groups = component_state.__meta__.groups
      entity_type = get_entity_type_component_module_for_entity(operation, entity)

      :ok =
        validate_locked_component(
          operation,
          operation.system_execution,
          component_module,
          entity_type
        )

      {{entity.id, component_module, component_groups}, component_state}
    end)
  end

  # Adds to, or creates the Entity's children and adds to or create the children's parents components
  defp create_children_and_parents(operation, entity, entity_type, []) do
    # Create empty children component for entity
    empty_entity_children = upsert_children_for(operation, entity, entity_type, [])
    [empty_entity_children]
  end

  defp create_children_and_parents(operation, entity, entity_type, children)
       when is_list(children) do
    entity_children = upsert_children_for(operation, entity, entity_type, children)

    entities_parents =
      Enum.map(children, fn child_entity ->
        # We need the entity_type_component_module of the child entity
        entity_type_component_module =
          get_entity_type_component_module_for_entity(operation, child_entity)

        upsert_parents_for(operation, child_entity, entity_type_component_module, [
          entity
        ])
      end)

    [entity_children | entities_parents]
  end

  # Adds to, or creates the Entity's parents and adds to or create the parent's children components
  defp create_parents_and_children(operation, entity, entity_type, []) do
    # Create empty parents component for entity
    empty_entity_parents = upsert_parents_for(operation, entity, entity_type, [])
    [empty_entity_parents]
  end

  defp create_parents_and_children(operation, entity, entity_type, parents)
       when is_list(parents) do
    entity_parents = upsert_parents_for(operation, entity, entity_type, parents)

    entities_children =
      Enum.map(parents, fn parent_entity ->
        # We need the entity_type_component_module of the parent entity
        entity_type_component_module =
          get_entity_type_component_module_for_entity(operation, parent_entity)

        upsert_children_for(operation, parent_entity, entity_type_component_module, [
          entity
        ])
      end)

    [entity_parents | entities_children]
  end

  # Returns a Children component with its key
  # {{entity_id, Component.Children, []}, [entity_3, entity_2, entity_1]}
  # it is calling upsert_component which will validate the component is locked for creation
  defp upsert_children_for(operation, entity, entity_type, children) do
    table = operation.components_state_ets_name

    case :ets.lookup(table, {entity.id, Component.Children, []}) do
      [{_key, %Component.Children{list: existing_children}}] ->
        children = Enum.concat(existing_children, children) |> Enum.uniq()
        upsert_component(operation, entity, {Component.Children, [list: children]}, entity_type)

      [] ->
        upsert_component(operation, entity, {Component.Children, [list: children]}, entity_type)
    end
  end

  # Returns a Parents component with its key
  # {{entity_id, Component.Parents, []}, [entity_3, entity_2, entity_1]}
  # it is calling upsert_component which will validate the component is locked for creation
  defp upsert_parents_for(operation, entity, entity_type, parents) do
    table = operation.components_state_ets_name

    case :ets.lookup(table, {entity.id, Component.Parents, []}) do
      [{_key, %Component.Parents{list: existing_parents}}] ->
        parents = Enum.concat(existing_parents, parents) |> Enum.uniq()
        upsert_component(operation, entity, {Component.Parents, [list: parents]}, entity_type)

      [] ->
        upsert_component(operation, entity, {Component.Parents, [list: parents]}, entity_type)
    end
  end

  # Mark for update: Remove children entities from  target Entity
  # and parent entity from their parents
  defp remove_children_and_parents(_operation, _entity, []), do: []

  defp remove_children_and_parents(operation, entity, children) when is_list(children) do
    table = operation.components_state_ets_name

    entity_children =
      case :ets.lookup(table, {entity.id, Component.Children, []}) do
        [{_key, %Component.Children{list: existing_children}}] ->
          entity_type = get_entity_type_component_module_for_entity(operation, entity)

          upsert_component(
            operation,
            entity,
            {Component.Children, [list: existing_children -- children]},
            entity_type
          )

        [] ->
          nil
      end

    entities_parents =
      Enum.map(children, fn child_entity ->
        # We need the entity_type_component_module of the child entity
        entity_type_component_module =
          get_entity_type_component_module_for_entity(operation, child_entity)

        case :ets.lookup(table, {child_entity.id, Component.Parents, []}) do
          [{_key, %Component.Parents{list: existing_parents}}] ->
            upsert_component(
              operation,
              child_entity,
              {Component.Parents, [list: existing_parents -- [entity]]},
              entity_type_component_module
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
    table = operation.components_state_ets_name

    entity_parents =
      case :ets.lookup(table, {entity.id, Component.Parents, []}) do
        [{_key, %Component.Parents{list: existing_parents}}] ->
          entity_type = get_entity_type_component_module_for_entity(operation, entity)

          upsert_component(
            operation,
            entity,
            {Component.Parents, [list: existing_parents -- parents]},
            entity_type
          )

        [] ->
          nil
      end

    entities_children =
      Enum.map(parents, fn parent_entity ->
        # We need the entity_type_component_module of the parent entity
        entity_type_component_module =
          get_entity_type_component_module_for_entity(operation, parent_entity)

        case :ets.lookup(table, {parent_entity.id, Component.Children, []}) do
          [{_key, %Component.Children{list: existing_children}}] ->
            upsert_component(
              operation,
              parent_entity,
              {Component.Children, [list: existing_children -- [entity]]},
              entity_type_component_module
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
    |> Enum.group_by(fn {k, _v} -> k end, fn {_k, v} -> v end)
    |> Enum.map(fn
      {k, [v]} ->
        {k, v}

      {{entity_id, module, _groups}, values} ->
        list = Enum.map(values, fn value -> value.list end) |> List.flatten() |> Enum.uniq()
        entity = Entity.build(entity_id)
        entity_type = get_entity_type_component_module_for_entity(operation, entity)

        upsert_component(operation, entity, {module, list: list}, entity_type)
    end)
  end

  defp group_removed_relations(operation, relations) do
    relations
    |> Enum.group_by(fn {k, _v} -> k end, fn {_k, v} -> v end)
    |> Enum.map(fn
      {k, [v]} ->
        {k, v}

      {{entity_id, module, _groups}, values} ->
        list =
          Enum.map(values, fn value -> value.list end)
          |> List.flatten()
          |> Enum.uniq()
          |> select_entities_present_in_all_relations(values)

        entity = Entity.build(entity_id)
        entity_type = get_entity_type_component_module_for_entity(operation, entity)

        upsert_component(operation, entity, {module, list: list}, entity_type)
    end)
  end

  defp select_entities_present_in_all_relations(entity_list, relations) do
    Enum.filter(
      entity_list,
      fn entity ->
        Enum.all?(
          relations,
          fn r -> entity in r.list end
        )
      end
    )
  end

  # Component CRUD Validations

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
    table = operation.components_state_ets_name

    Enum.each(entity_ids, fn entity_id ->
      f =
        Ex2ms.fun do
          {{^entity_id, _component_module, _component_groups}, _component_state} -> ^entity_id
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
    table = operation.components_state_ets_name
    entity_ids = Enum.map(entities, & &1.id)

    # All this, just because `when entity_id in ^entity_ids` doesn't work :(

    result =
      entity_ids
      |> Stream.map(fn target_entity_id ->
        f =
          Ex2ms.fun do
            {{entity_id, _component_module, _groups}, _component_state}
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
        raise Error, {operation, "Entity ids `#{inspect(missing_entity_ids)}` do not exist."}
    end
  end

  defp validate_is_component(operation, component_module) do
    try do
      if component_module.__ecs_type__() == :component do
        :ok
      else
        raise "validation error"
      end
    rescue
      _ ->
        reraise Error,
                {operation, "#{inspect(component_module)} is not a Component"}
    end
  end

  defp validate_no_relation(operation, component_specs) do
    component_modules =
      Enum.map(component_specs, fn
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
                 "#{inspect(component_state_struct)} state is invalid. Error: #{inspect(error)}"}
      end
    else
      :ok
    end
  end

  # There is no lock validation for sync systems
  defp validate_locked_component(operation, :sync, component_module, _entity_type) do
    unless Enum.empty?(operation.locked_components) do
      Logger.warn(
        "#{inspect(operation)}. Component: #{inspect(component_module)}. There is no need to lock components in Systems that execute synchronously. The values are ignored"
      )
    end

    :ok
  end

  # when the Entity does not have an entity_type component assigned yet
  defp validate_locked_component(operation, :async, component_module, nil) do
    locked_components = operation.locked_components

    if component_module in locked_components do
      :ok
    else
      raise Error,
            {operation,
             "#{inspect(component_module)} is not locked. It can not be created or updated in an async System"}
    end
  end

  defp validate_locked_component(operation, :async, component_module, entity_type) do
    locked_components = operation.locked_components

    if component_module in locked_components or
         {component_module, entity_type: entity_type} in locked_components do
      :ok
    else
      raise Error,
            {operation,
             "#{inspect(component_module)} is not locked. It can not be created or updated in an async System"}
    end
  end

  # here we don't have to consider the case when the entity_type_component_module is nil
  # the entity type should be found before executing this function by checking
  # newly added components or existing components
  defp validate_entity_type_component(operation, component_module, entity_type_component_module) do
    if component_module.__component_access_mode__() == :entity_type and
         component_module != entity_type_component_module do
      raise Error,
            {operation,
             "Component #{inspect(component_module)} has `access_mode: entity_type`. The entity already has a component with `access_mode: :entity_type`: #{inspect(entity_type_component_module)}."}
    else
      :ok
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
            {component_module, _} when is_atom(component_module) -> component_module
            component_module when is_atom(component_module) -> component_module
          end)

        if component_modules -- existing_components == component_modules do
          :ok
        else
          duplicates = component_modules -- component_modules -- existing_components

          raise Error,
                {operation,
                 "Components #{inspect(duplicates)} already exist for the entity #{inspect(entity_id)}"}
        end
    end
  end

  defp validate_component_exists(operation, component) do
    table = operation.components_state_ets_name

    case :ets.lookup(
           table,
           {component.__meta__.entity.id, component.__meta__.module, component.__meta__.groups}
         ) do
      [{_key, _val}] -> :ok
      _ -> raise Error, {operation, "#{inspect(component)} does not exist"}
    end
  end

  defp validate_component_writable(operation, component) do
    if component.__meta__.access_mode == :write do
      :ok
    else
      raise Error,
            {operation,
             "#{inspect(component)} has no write access. Cannot update a component without access_mode: :write."}
    end
  end

  # Resources CRUD validations

  defp validate_is_resource(operation, {resource_module, _state}) do
    validate_is_resource(operation, resource_module)
  end

  defp validate_is_resource(operation, resource_module) do
    try do
      if resource_module.__ecs_type__() == :resource do
        :ok
      else
        raise "validation error"
      end
    rescue
      _ ->
        reraise Error,
                {operation, "#{inspect(resource_module)} is not a Resource"}
    end
  end

  defp validate_resource_state(operation, resource_state_struct) do
    if function_exported?(resource_state_struct.__meta__.module, :validate, 1) do
      case resource_state_struct.__meta__.module.validate(resource_state_struct) do
        :ok ->
          :ok

        {:error, error} ->
          raise Error,
                {operation,
                 "#{inspect(resource_state_struct)} state is invalid. Error: #{inspect(error)}"}
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
           "Resource commands are supported only in sync Systems (startup_systems, frame_start_system, frame_end_system). Resource: #{inspect(resource_module)} "}
  end

  defp validate_resource_does_not_exist(operation, resource_spec) do
    resource_module =
      case resource_spec do
        {resource_module, _} when is_atom(resource_module) -> resource_module
        resource_module when is_atom(resource_module) -> resource_module
      end

    table = operation.resources_state_ets_name

    case :ets.lookup(table, resource_module) do
      [] ->
        :ok

      _ ->
        raise Error,
              {operation, "Resource #{inspect(resource_module)} already exists"}
    end
  end

  defp validate_resource_exists(operation, resource) do
    table = operation.resources_state_ets_name

    case :ets.lookup(table, resource.__meta__.module) do
      [{_key, _val}] -> :ok
      _ -> raise Error, {operation, "#{inspect(resource)} does not exist"}
    end
  end

  defp validate_resource_writable(operation, resource) do
    if resource.__meta__.access_mode == :write do
      :ok
    else
      raise Error,
            {operation,
             "#{inspect(resource)} has no write access. Cannot update a resource without access_mode: :write."}
    end
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
    table = Process.get(:components_state_ets_name)

    # do not allow multiple operations for the same component
    unique_components = Enum.uniq_by(components, fn {key, _val} -> key end)

    duplicates = components -- unique_components

    case duplicates do
      [] ->
        :ets.insert(table, components)
        # invalidate the cache when inserting new components
        Memoize.invalidate()
        component_created_events(components)
        :ok

      _ ->
        raise "Error inserting components. Duplicate components insert is not allowed in the same Command: #{inspect(duplicates)}"
    end
  end

  defp commit_updates([]), do: :ok

  defp commit_updates(components) do
    table = Process.get(:components_state_ets_name)

    # do not allow multiple operations for the same component
    unique_components = Enum.uniq_by(components, fn {key, _val} -> key end)

    duplicates = components -- unique_components

    case duplicates do
      [] ->
        :ets.insert(table, components)

        relation_updates =
          Enum.filter(components, fn {{_entity_id, module, _groups}, _component} ->
            module in [Ecspanse.Component.Children, Ecspanse.Component.Parent]
          end)

        if Enum.any?(relation_updates) do
          # invalidate the cache when updating Children or Parents
          Memoize.invalidate()
        end

        component_updated_events(components)
        :ok

      _ ->
        raise "Error updating components. Duplicate components update is not allowed in the same Command: #{inspect(duplicates)}"
    end
  end

  defp commit_deletes([]), do: :ok

  defp commit_deletes(components) do
    table = Process.get(:components_state_ets_name)

    Enum.each(components, fn {key, _val} ->
      :ets.delete(table, key)
    end)

    # invalidate the cache when deleting components
    Memoize.invalidate()

    component_deleted_events(components)

    :ok
  end

  # helper query functions

  # looks filters through entity components to see if any has `access_mode: :entity_type`
  defp get_entity_type_component_module_for_entity(operation, %Entity{id: entity_id}) do
    entities_components = operation.entities_components

    result =
      case entities_components[entity_id] do
        [] ->
          []

        nil ->
          []

        components when is_list(components) ->
          components
          |> Enum.filter(&(&1.__component_access_mode__() == :entity_type))
      end

    case result do
      [component_module] ->
        component_module

      [] ->
        nil

      list ->
        raise Error,
              {operation,
               "An entity has more than one entity_type component: #{inspect(list)}. All entities may have only one component with `access_mode: :entity_type`"}
    end
  end

  defp get_entity_type_component_module_form_component_specs(operation, component_specs) do
    result =
      component_specs
      |> Enum.filter(fn
        module when is_atom(module) ->
          module.__component_access_mode__() == :entity_type

        {module, _state} ->
          module.__component_access_mode__() == :entity_type
      end)
      |> Enum.map(fn
        module when is_atom(module) -> module
        {module, _state} -> module
      end)

    case result do
      [component_module] ->
        component_module

      [] ->
        nil

      list ->
        raise Error,
              {operation,
               "An entity has more than one entity_type component: #{inspect(list)}. All entities may have only one component with `access_mode: :entity_type`"}
    end
  end

  defp recursive_children_entities(_operation, [], acc) do
    acc
  end

  defp recursive_children_entities(operation, entities, acc) do
    children =
      Query.select({Component.Children}, for: entities)
      |> Query.stream(operation.token)
      |> Stream.map(fn {%Component.Children{list: children}} -> children end)
      |> Enum.concat()

    # avoid circular dependencies
    children = children -- acc

    recursive_children_entities(operation, children, acc ++ children)
  end

  ### Special Events

  defp component_created_events(components) do
    components
    |> Enum.map(fn {_key, component} ->
      {{Event.ComponentCreated, component.__meta__.entity.id},
       struct!(Event.ComponentCreated, %{
         created: component,
         inserted_at: System.os_time()
       })}
    end)
    |> add_events()
  end

  defp component_updated_events(components) do
    components
    |> Enum.map(fn {_key, component} ->
      {{Event.ComponentUpdated, component.__meta__.entity.id},
       struct!(Event.ComponentUpdated, %{
         updated: component,
         inserted_at: System.os_time()
       })}
    end)
    |> add_events()
  end

  defp component_deleted_events(components) do
    components
    |> Enum.map(fn {_key, component} ->
      {{Event.ComponentDeleted, component.__meta__.entity.id},
       struct!(Event.ComponentDeleted, %{
         deleted: component,
         inserted_at: System.os_time()
       })}
    end)
    |> add_events()
  end

  defp resource_created_event(resource) do
    event =
      {{Event.ResourceCreated, resource.__meta__.module},
       struct!(Event.ResourceCreated, %{
         created: resource,
         inserted_at: System.os_time(:millisecond)
       })}

    add_events([event])
  end

  defp resource_updated_event(resource) do
    event =
      {{Event.ResourceUpdated, resource.__meta__.module},
       struct!(Event.ResourceUpdated, %{
         updated: resource,
         inserted_at: System.os_time(:millisecond)
       })}

    add_events([event])
  end

  defp resource_deleted_event(resource) do
    event =
      {{Event.ResourceDeleted, resource.__meta__.module},
       struct!(Event.ResourceDeleted, %{
         deleted: resource,
         inserted_at: System.os_time(:millisecond)
       })}

    add_events([event])
  end

  defp add_events(events) when is_list(events) do
    table = Process.get(:events_ets_name)
    :ets.insert(table, events)
  end
end
