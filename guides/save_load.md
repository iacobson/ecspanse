# Saving and Loading

With the introduction of the `Ecspanse.Snapshot` module, it is now possible to implement custom save and load functionalities. Let's explore some strategies and potential pitfalls.

## Generic Info

### Running Snapshot Functions

The `Ecspanse.Snapshot` functions should run in synchronous Systems.
Depending on the project needs they may run:

- at startup and shutdown:

```elixir
def setup(data) do
  data
  |> add_startup_system(Demo.Systems.Load)
  # ...
  |> add_shutdown_system(Demo.Systems.Save)
end
```

- on demand, in systems that listed to save/load events:

```elixir
def setup(data) do
  data
  |> add_frame_start_system(Demo.Systems.Load)
  # ...
  |> add_frame_end_system(Demo.Systems.Save)
end
```

The logic can be further refined with conditional systems (`run_in_state | run_not_in_state`) and `Ecspanse.State`.

### Restoring functions

The restoring functions are overwriting the existing entities components or resources. That means if the entity with id "1" and component "A" exists, and a restore function is called for the same entity and component, the component "A" state and tags will be replaced with the one from the restore. Restoring will not affect other existing components of the entity "1" that are not in the scope of the restore.

If the logic requires despawning potentially existing entities before restoring, the following pattern may be used:

```elixir
case Ecspanse.Query.fetch_entity(entity_id) do
  {:ok, entity} -> Ecspanse.Command.despawn_entity_and_descendants!(entity)
  _ -> :ok
end
Ecspanse.Snapshot.restore_entity!(entity_id, component_specs_list)
```

### Versioning

The `Ecspanse.Snapshot.EntitySnapshot` and `Ecspanse.Snapshot.ResourceSnapshot` structs have a `version :: integer()` field that can be used to manage backwards compatibility. The version can be used to determine how to restore the entity or resource.

It is the developer's responsibility to provide and update the version field.

```elixir
defmodule TestServer1 do
  use Ecspanse, fps_limit: 60, version: 1

  def setup(data) do
    # ...
  end
end
```

Then, upon introduction of a breaking change, the version can be updated: e.g. `2`.

For example, we have an entity snapshot with version `3`. Meanwhile, the module name for one of the entity components has changed. At this point a 1-to-1 restore will fail, as the old module does not exist anymore. However, being able to check the version, we can intercept the payload and transform it to the new module. More on this in the [Custom Save and Load](#custom-save-and-load-for-backwards-compatibility) section below.

## Basic 1-to-1 Save and Load

The easiest approach is to use the provided `Ecspanse.Snapshot.EntitySnapshot` and `Ecspanse.Snapshot.ResourceSnapshot` structs to save and load entities and resources.

The code below would export all components grouped by entity as a list of `Ecspanse.Snapshot.EntitySnapshot` structs.

```elixir
snapshots = Ecspanse.Snapshot.export_entities!()
```

And this will restore the entities from the list of `Ecspanse.Snapshot.EntitySnapshot` structs.

```elixir
Ecspanse.Snapshot.restore_entities_from_snapshots!(snapshots)
```

That's it!

## Persisting the Snapshots

The persistence mechanism is beyond the scope of the `Ecspanse` library. This chapter provides some considerations on the topic.

### Encode and Decode

Probably the most common and easiest way to persist data is to encode it to a binary format and save it to a file. It is however important to consider the security implications of this approach. [Here are some good explanations](https://erlef.github.io/security-wg/secure_coding_and_deployment_hardening/serialisation) of the risks and how to mitigate them.

The `:safe` options that prevents the creation of new atoms may require special attention. For example if the one encoded component has some atom tags, and the current code does not use those tags anymore, the decoding with `:safe` option will fail. The same would happen also for any atom in the component state that does not exist anymore in the current code.

### Database Persistence

In essence, the complexity of the project's components directly influences the difficulty of the task. `Ecspanse.Component` supports any type of data within its state, including deeply nested structs with lists of atoms as fields. This can pose a challenge when modeling in a database.

However, projects with simpler components can be more easily persisted in a database.

## Filtering

Not every component, entity, or resource needs to be saved. Both `Ecspanse.Component` and `Ecspanse.Resource` include an `export_filter` option, which defaults to `:none`, to filter the data that is exported.

Filtering out a component type from all entities:

```elixir
defmodule Demo.Components.MyComponent do
  use Ecspanse.Component, export_filter: :component
end
```

Filtering out entities with a specific component. This is specially useful for components used as tags. For example, in a game happening in a forrest where many leaves that are purely decorative are floating in the background. We decide we do not want to export the leaves but to generate them on demand when the game loads. For this we could add a stateless component `Demo.Components.Leaf` to the leaves entities and filter the entity out from the export. Even if the leaf entity has more components like `Demo.Components.Position` or `Demo.Components.Velocity`, none of them will be exported.

```elixir
defmodule Demo.Components.Leaf do
  use Ecspanse.Component, export_filter: :entity
end
```

Filtering out a resource:

```elixir
defmodule Demo.Resources.MyResource do
  use Ecspanse.Resource, export_filter: :resource
end
```

## Custom Save and Load for Backwards Compatibility

As highlighted in the [Versioning](#versioning) section, exporting and importing data in a 1-to-1 manner is not always feasible. Code and data evolve over time, and saved data may become outdated. In such cases, a custom save and load mechanism is required. `Ecspanse.Snapshot` provides functions restore entities and resources from `t:Ecspanse.Component.component_spec/0` and `t:Ecspanse.Resource.resource_spec/0` that can be composed by traversing the snapshots.

Let's consider a scenario where we have a `Demo.Components.OldComponent` that has been renamed to `Demo.Components.NewComponent`:

```elixir
# iterating the component specs in an EntitySnapshot
specs = for component_spec <- entity_snapshot.component_specs do
  case component_spec do
    {Demo.Components.OldComponent, state, tags} ->
      {Demo.Components.NewComponent, state, tags}
    _ -> component_spec
  end
end

Ecspanse.Snapshot.restore_entity!(entity_snapshot.id, specs)
```

## Managing Invalid Entity Relationships

When working with `Ecspanse.Command` to create inter-entity relationships, the library performs checks to ensure that these relationships are valid. It uses a reflection mechanism to ensure both parent and child entities are aware of each other. Consequently, developers do not need to manually insert, remove, or update `Ecspanse.Component.Parent` or `Ecspanse.Component.Child` components.

In contrast, `Ecspanse.Snapshot` takes a naive approach. The `Ecspanse.Component.Parent` and `Ecspanse.Component.Child` components are treated like any other components. Restoring an entity with children does not automatically restore the child entities. Unless these child entities are also included in the list of entities to be restored, the parent entity will contain invalid relationships.

Building upon the previous [forest](#filtering) example, let's consider a scenario where leaf entities are children of tree entities. If we decide to export the trees but not the leaves, the trees will be restored without their leaf children. However, the tree entities will still reference the leaves in their `Ecspanse.Component.Child` component, resulting in an invalid relationship. This won't break the logic but may lead to unexpected behavior or confusion.

To address this issue, developers can manually despawn existing leaf entities or remove their relationship with the trees before exporting. However, this approach may not always be feasible. In such cases, `Ecspanse.Snapshot` provides two functions to help manage invalid entity relationships:

- `Ecspanse.Snapshot.show_invalid_relationships/0` - This function should be run after the restoration process is completed. It will print a list of entities with their invalid relationships.
- `Ecspanse.Snapshot.remove_invalid_relationships!/0` - If invalid relationships are expected, this function can be called to remove all of them.
