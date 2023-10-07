# Changelog

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

- removed the automatically generated events: `Ecspanse.Event.{ComponentCreated, ComponentUpdated, ComponentDeleted, ResourceCreated, ResourceUpdated, ResourceDeleted}`. Use custom emitted events or short-lived components instead.

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

- introducing `Ecspanse.Template.Component` and `Ecspanse.Template.Event` to simplify the creation of related components and events.
- adds a new query `Ecspanse.Query.fetch_component/2` to fetch a system's component by a list of tags.

## v0.1.2 (2023-08-14)

### Fixes

- removes unneeded dependency `plug_crypto`
- upgrades dependencies: `credo`, `ex_doc`, `jason`

## v0.1.1 (2023-08-12)

### Fixes

- adds the missing project `:package`
