defmodule Ecspanse.Snapshot do
  @moduledoc """
  Provides functions to export and restore Entities and Resources.
  Those can be used to implement custom save/load functionality.

  All functions in this module must be executed from synchronous Systems.

  The 'export filter' or 'unfiltered' terms in the functions documentation refers to the `:export_filter`
  option, available for `Ecspanse.Component` and `Ecspanse.Resource`. This option can filter
  out components and resources from the export process.

  > #### Attention  {: .warning}
  > All restore functions are overwriting any existing entity components or resources.

  [Some examples](./save_load.md) are available in the documentation.
  """
  alias Ecspanse.Util

  require Ex2ms

  defp build_operation(operation_name) do
    unless Process.get(:ecs_process_type) == :system do
      raise "Commands can only be executed from a System."
    end

    operation = %Ecspanse.Command.Operation{
      name: operation_name,
      system: Process.get(:system_module),
      entities_components: %{},
      system_execution: Process.get(:system_execution),
      locked_components: Process.get(:locked_components)
    }

    unless operation.system_execution == :sync do
      raise Ecspanse.Command.Error,
            {operation,
             "Snapshot functions can only be executed from a synchronous System. The module #{operation.system} is not a synchronous System."}
    end

    operation
  end

  defmodule EntitySnapshot do
    @moduledoc """
    An entity snapshot.

    The `:version` field is the value provided in the `use Ecspanse, version: x` at the time of export.
    This value is used to ensure compatibility when restoring entities.
    """
    @type t :: %__MODULE__{
            version: integer(),
            entity_id: Ecspanse.Entity.id(),
            component_modules: list(module()),
            component_specs: list(Ecspanse.Component.component_spec())
          }

    defstruct version: nil, entity_id: nil, component_modules: [], component_specs: []
  end

  defmodule ResourceSnapshot do
    @moduledoc """
    A resource snapshot.

    The `:version` field is the value provided in the `use Ecspanse, version: x` at the time of export.
    This value is used to ensure compatibility when restoring entities.
    """
    @type t :: %__MODULE__{
            version: integer(),
            resource_module: module(),
            resource_spec: Ecspanse.Resource.resource_spec()
          }

    defstruct version: nil, resource_module: nil, resource_spec: nil
  end

  @doc """
  Exports all entities and their components without export filters.

  Returns a list of entity snapshots.
  """
  @doc group: :export
  @spec export_entities!() :: list(EntitySnapshot.t())
  def export_entities! do
    build_operation(:export_entities)
    build_entities_snapshot(query_all_raw_components())
  end

  @doc """
  Exports a specific entity and its unfiltered components.

  Returns the entity snapshot, or `nil` if the entity does not exist.
  """
  @doc group: :export
  @spec export_entity!(Ecspanse.Entity.t()) :: EntitySnapshot.t() | nil
  def export_entity!(%Ecspanse.Entity{} = entity) do
    operation = build_operation(:export_entities)

    entities =
      [entity.id]
      |> query_raw_components_for()
      |> build_entities_snapshot()

    case entities do
      [entity] -> entity
      [] -> nil
      _ -> raise Ecspanse.Command.Error, {operation, "Multiple entities found: #{entity.id}"}
    end
  end

  @doc """
  Exports a specific entity with it's descendants and their unfiltered components.

  Returns a list of entity snapshots.
  """
  @doc group: :export
  @spec export_entity_with_descendants!(Ecspanse.Entity.t()) :: list(EntitySnapshot.t())
  def export_entity_with_descendants!(%Ecspanse.Entity{} = entity) do
    build_operation(:export_entities)
    descendants = Ecspanse.Query.list_descendants(entity)

    [entity | descendants]
    |> Enum.map(& &1.id)
    |> query_raw_components_for()
    |> build_entities_snapshot()
  end

  @doc """
  Exports a list of custom entities and their unfiltered components.

  Returns a list of entity snapshots.
  """
  @doc group: :export
  @spec export_custom_entities!(list(Ecspanse.Entity.t())) :: list(EntitySnapshot.t())
  def export_custom_entities!(entities) do
    build_operation(:export_entities)

    entities
    |> Enum.map(& &1.id)
    |> query_raw_components_for()
    |> build_entities_snapshot()
  end

  defp get_ecs_version do
    version = Process.get(:ecs_version)

    if is_integer(version) and version >= 0 do
      version
    else
      raise "Invalid version: #{version}. The Version must be a positive integer. See the `Ecspanse` module documentation for details."
    end
  end

  defp query_all_raw_components do
    table = Util.components_state_ets_table()

    f =
      Ex2ms.fun do
        {{entity_id, component_module}, component_tags, component} ->
          {entity_id, component_module, component_tags, component}
      end

    :ets.select(table, f)
  end

  defp query_raw_components_for(entity_ids) do
    table = Util.components_state_ets_table()

    f =
      Ex2ms.fun do
        {{entity_id, component_module}, component_tags, component} ->
          {entity_id, component_module, component_tags, component}
      end

    table
    |> :ets.select(f)
    |> Enum.filter(fn {entity_id, _, _, _} -> Enum.member?(entity_ids, entity_id) end)
  end

  defp build_entities_snapshot(raw_components) do
    raw_components =
      Enum.reject(raw_components, fn {_, _, _, component} -> component.__meta__.export_filter == :component end)

    rejected_entity_ids =
      raw_components
      |> Enum.filter(fn {_, _, _, component} -> component.__meta__.export_filter == :entity end)
      |> Enum.map(fn {entity_id, _, _, _} -> entity_id end)
      |> Enum.uniq()

    raw_components
    |> Enum.reject(fn {entity_id, _, _, _} -> Enum.member?(rejected_entity_ids, entity_id) end)
    |> Enum.group_by(
      fn {entity_id, _, _, _} -> entity_id end,
      fn {_entity_id, component_module, component_tags, component} ->
        component_state = component |> Map.from_struct() |> Map.drop([:__meta__]) |> Map.to_list()
        component_specs = {component_module, component_state, MapSet.to_list(component_tags)}
        component_specs
      end
    )
    |> Enum.map(fn {entity_id, component_specs} ->
      %EntitySnapshot{
        version: get_ecs_version(),
        entity_id: entity_id,
        component_modules: Enum.map(component_specs, fn {component_module, _, _} -> component_module end),
        component_specs: component_specs
      }
    end)
  end

  @doc """
  Exports all resources without export filters.

  Returns a list of resource snapshots.
  """
  @doc group: :export
  @spec export_resources!() :: list(ResourceSnapshot.t())
  def export_resources! do
    build_operation(:export_resources)
    table = Util.resources_state_ets_table()

    f =
      Ex2ms.fun do
        {resource_module, resource} ->
          {resource_module, resource}
      end

    table
    |> :ets.select(f)
    |> Enum.reject(fn {_, resource} -> resource.__meta__.export_filter == :resource end)
    |> Enum.map(fn {resource_module, resource} ->
      %ResourceSnapshot{
        version: get_ecs_version(),
        resource_module: resource_module,
        resource_spec: {resource_module, resource |> Map.from_struct() |> Map.drop([:__meta__]) |> Map.to_list()}
      }
    end)
  end

  @doc """
  Restores entities and components from a list of entity snapshot structs.
  """
  @doc group: :restore
  @spec restore_entities_from_snapshots!(list(EntitySnapshot.t())) :: :ok
  def restore_entities_from_snapshots!(entity_snapshots) do
    entity_snapshots
    |> Enum.map(&{&1.entity_id, &1.component_specs})
    |> restore_entities!()
  end

  @doc """
  Restores resources from a list of resource snapshot structs.
  """
  @doc group: :restore
  @spec restore_resources_from_snapshots!(list(ResourceSnapshot.t())) :: :ok
  def restore_resources_from_snapshots!(resource_snapshots) do
    resource_snapshots
    |> Enum.map(& &1.resource_spec)
    |> restore_resources!()
  end

  @doc """
  Restores an entity and components from an entity ID and a list of component specs.
  """
  @doc group: :restore
  @spec restore_entity!(Ecspanse.Entity.id(), list(Ecspanse.Component.component_spec())) :: :ok
  def restore_entity!(entity_id, component_specs) do
    restore_entities!([{entity_id, component_specs}])
  end

  @doc """
  Restores entities and their components from a list of entity IDs and component specs.
  """
  @doc group: :restore
  @spec restore_entities!(list({Ecspanse.Entity.id(), list(Ecspanse.Component.component_spec())})) :: :ok
  def restore_entities!(data) do
    operation = build_operation(:restore_entities)

    records =
      Enum.flat_map(
        data,
        fn {entity_id, component_specs} ->
          entity = Util.build_entity(entity_id)
          Ecspanse.Command.upsert_components(operation, entity, component_specs, [])
        end
      )

    Ecspanse.Command.commit_inserts(records)
    :ok
  end

  @doc """
  Restores a resource from a resource spec.
  """
  @doc group: :restore
  @spec restore_resource!(Ecspanse.Resource.resource_spec()) :: :ok
  def restore_resource!(resource_spec) do
    restore_resources!([resource_spec])
  end

  @doc """
  Restores resources from a list of resource specs.
  """
  @doc group: :restore
  @spec restore_resources!(list(Ecspanse.Resource.resource_spec())) :: :ok
  def restore_resources!(resource_specs) do
    operation = build_operation(:restore_resources)
    Enum.each(resource_specs, &Ecspanse.Command.upsert_resource(operation, &1))
    :ok
  end

  @doc """
  Shows invalid relationships between entities.

  The result is a map with two keys: `:invalid_parent_relationships` and `:invalid_child_relationships`.
  Each key contains a list of tuples with the current entity and the list of invalid entities.
  """
  @doc group: :relationships
  @spec show_invalid_relationships() :: %{
          invalid_child_relationships: list({Ecspanse.Entity.t(), list(Ecspanse.Entity.t())}),
          invalid_parent_relationships: list({Ecspanse.Entity.t(), list(Ecspanse.Entity.t())})
        }
  def show_invalid_relationships do
    build_operation(:invalid_relationships)
    raw_components = query_all_raw_components()

    current_entity_ids =
      Enum.map(raw_components, fn {entity_id, _, _, _} -> entity_id end)

    invalid_parent_relations =
      for {entity_id, _, _, component} <- raw_components, reduce: [] do
        acc ->
          case component do
            %Ecspanse.Component.Parents{entities: parent_entities} ->
              invalid = Enum.reject(parent_entities, fn entity -> Enum.member?(current_entity_ids, entity.id) end)

              case invalid do
                [] ->
                  acc

                _ ->
                  [{Util.build_entity(entity_id), invalid} | acc]
              end

            _ ->
              acc
          end
      end

    invalid_child_relations =
      for {entity_id, _, _, component} <- raw_components, reduce: [] do
        acc ->
          case component do
            %Ecspanse.Component.Children{entities: child_entities} ->
              invalid = Enum.reject(child_entities, fn entity -> Enum.member?(current_entity_ids, entity.id) end)

              case invalid do
                [] ->
                  acc

                _ ->
                  [{Util.build_entity(entity_id), invalid} | acc]
              end

            _ ->
              acc
          end
      end

    %{
      invalid_parent_relationships: invalid_parent_relations,
      invalid_child_relationships: invalid_child_relations
    }
  end

  @doc """
  Removes the invalid relationships between entities.
  See `Ecspanse.Snapshot.show_invalid_relationships/0` for more details.
  """
  @doc group: :relationships
  @spec remove_invalid_relationships!() :: :ok
  def remove_invalid_relationships! do
    invalid_relationships = show_invalid_relationships()

    Ecspanse.Command.remove_parents!(invalid_relationships.invalid_parent_relationships)
    Ecspanse.Command.remove_children!(invalid_relationships.invalid_child_relationships)

    :ok
  end
end
