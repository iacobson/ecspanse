# Changelog

## v0.10.0 (2024-09-25)

### Features

- introduces `Ecspanse.Snapshot` to enable custom save and load functionalities.
  - `use Ecspanse` accepts now the `:version` option to ensure backwards compatibility when restoring entities and resources.
  - `use Ecspanse.Component` and `use Ecspanse.Resource` accept now the `:export_filter` option.
- new [guides section](https://hexdocs.pm/ecspanse/save_load.html) for save and load.

## v0.9.0 (2024-03-30)

### Breaking

- removes `Ecspanse.Resource.State` in favor of `Ecspanse.State` functionality.

#### Replacing the old `Ecspanse.Resource.State` with `Ecspanse.State`

##### Creating a new state

```elixir
defmodule Demo.States.Game do
  use Ecspanse.State, states: [:play, :paused], default: :play
end
```

Multiple states can be defined in the same way:

```elixir
defmodule Demo.States.Area do
  use Ecspanse.State, states: [:dungeon, :market, :forrest], default: :forrest
end
```

##### Conditionally running systems

Old code:

```elixir
Ecspanse.add_system(
  ecspanse_data,
  Demo.Systems.MoveHero,
  run_in_state: [:play]
)
```

New code:

```elixir
Ecspanse.add_system(
  ecspanse_data,
  Demo.Systems.MoveHero,
  run_in_state: {Demo.States.Game, :play}
)
```

##### Getting and setting states

Old code:

```elixir
{:ok, %Ecspanse.Resource.State{value: state}} = Ecspanse.Query.fetch_resource(Ecspanse.Resource.State)
Ecspanse.Command.update_resource!(Ecspanse.Resource.State, value: :paused)
```

New code:

```elixir
:play == Demo.States.Game.get_state!()

# Attention! The system running this command must be synchronous.
:ok = Demo.States.Game.set_state!(:paused)
```

##### Listening to state changes

```elixir
defmodule Demo.Systems.OnGamePaused do
  use Ecspanse.System, event_subscriptions: [Ecspanse.Event.StateTransition]

  def run(%Ecspanse.Event.StateTransition{module: Demo.States.Game, previous_state: _, current_state: :paused}) do
    # logic
  end

  def run(_event), do: :ok
end

```

### Features

- allows inserting resources at startup with `Ecspanse.insert_resource/2`
- allows state init at startup with `Ecspanse.init_state/2`
- introduces `Ecspanse.State` state functionalities. See the breaking changes for more details.
- new library built-in `Ecspanse.Event.StateTransition` event
- new library built-in `Ecspanse.Component.Name` component

### Improvements

- `Ecspanse.Query.entity_exists?/1` to check if an entity still exists
- `Ecspanse.Command.add_and_fetch_component!/2` wrapper to return a component after creation
- `Ecspanse.Command.update_and_fetch_component!/2` wrapper to return a component after update

## v0.8.1 (2023-12-22)

### Improvements

- returns an explicit error message when trying to run queries or create events and the Ecspanse server is not running.
- documentation improvements.

## v0.8.0 (2023-11-14)

### Improvements

- refactor the `Ecspanse.Projection` to include the state of the projection
  - the projection result is now wraped in a `Ecspanse.Projection{}` struct, together with the projection state.
  - the `c:Ecspanse.Projection.project/1` callback returns now the projection state as well as the projection result.

### Breaking

- the `Projection.run?/2` callback has been removed. The functionality is now handled by the `c:Ecspanse.Projection.project/1` callback, by returning `:halt`.
- the `c:Ecspanse.Projection.project/1` callback should now return also the state of the projection. See the documentation for more details.
- the `c:Ecspanse.Projection.on_change/3` callback takes as second and third argument the `t:Ecspanse.Projection.t/0`.
- the `c:Ecspanse.Projection.get!/1` callback now returns a `t:Ecspanse.Projection.t/0`.

## v0.7.3 (2023-11-13)

### Improvements

- implement the `Projection.run?/2` optional callback to run projections conditionally.

## v0.7.2 (2023-11-05)

### Improvements

- `c:Ecspanse.Projection.on_change/3` is called on Projection server initialization.

## v0.7.1 (2023-10-07)

### Improvements

- `Ecspanse.Command.clone_entity!/2` and `Ecspanse.Command.deep_clone_entity!/2` now accept an `:id` option to set the id of the cloned entity.

## v0.7.0 (2023-10-05)

### Breaking

- `c:Ecspanse.Projection.on_change/3` replaces the `on_change/2` and now takes both the new projection as well as the previous projection as arguments.

### Improvements

- updating projections after all frame systems have run to return a consistent state.

## v0.6.0 (2023-10-02)

### Features

- introduces `Ecspanse.Projection` to build state projections across entities and components.

## v0.5.0 (2023-09-28)

### Features

- introduces ancestors queries to query for parents of an entity, the parents of parents, and so on:
  - `Ecspanse.Query.select/2` new option: `:for_ancestors_of`
  - `Ecspanse.Query.list_ancestors/1`
  - `Ecspanse.Query.list_tagged_components_for_ancestors/2`

## v0.4.0 (2023-09-17)

### Breaking

- removes the automatically generated events: `Ecspanse.Event.{ComponentCreated, ComponentUpdated, ComponentDeleted, ResourceCreated, ResourceUpdated, ResourceDeleted}`. Use custom emitted events or short-lived components instead.

### Improvements

- improves performance for tagged components. The system loop now runs faster when dealing with tagged components.

## v0.3.1 (2023-08-30)

### Fixes

- fixes a bug where events could be scheduled after they were batched for the current frame, and before the current events are cleared. Causing some events to be lost. Thanks to [@andzdroid](https://github.com/andzdroid) for identifying and documenting the issue.
- fixes a bug where temporary timers would crash. Thanks to [@holykol](https://github.com/holykol) for finding and fixing the issue.

### Features

- imports `Ecspanse.Query` and `Ecspanse.Command` in all systems, so all the queries and commands are available without needing the respective module prefix.
- imports `Ecspanse` in the setup module that `use Ecspanse` so the system scheduling functions are available without needing the module prefix.

## v0.3.0 (2023-08-21)

### Features

- adds a new query `Ecspanse.Query.list_tags/1` to list a component's tags.
- adds a new query `Ecspanse.Query.list_components/1` to list all components of an entity.
- adds a new command `Ecspanse.Command.clone_entity!/1` to clone an entity without its relationships.
- adds a new command `Ecspanse.Command.deep_clone_entity!/1` to clone an entity with its descendants.

## v0.2.1 (2023-08-20)

### Fixes

- batch all events only by `batch_key` to avoid race conditions for different events processed by the same system.

## v0.2.0 (2023-08-18)

### Breaking

- `use Ecspanse.Component.Timer` and `use Ecspanse.Event.Timer` are now deprecated.
  Use `use Ecspanse.Template.Component.Timer` and `use Ecspanse.Template.Event.Timer` instead.

### Features

- introduces `Ecspanse.Template.Component` and `Ecspanse.Template.Event` to simplify the creation of related components and events.
- adds a new query `Ecspanse.Query.fetch_component/2` to fetch a system's component by a list of tags.

## v0.1.2 (2023-08-14)

### Fixes

- removes unneeded dependency `plug_crypto`
- upgrades dependencies: `credo`, `ex_doc`, `jason`

## v0.1.1 (2023-08-12)

### Fixes

- adds the missing project `:package`
