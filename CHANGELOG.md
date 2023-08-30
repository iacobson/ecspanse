# Changelog

## v0.3.1 (2023-08-30)

### Fixes

- fixes a bug where evetns could be scheduled after they were batched for the current frame, and before the current events are cleared.
  That was causing some events to be lost. Thanks to @andzdroid for identifying and documenting the issue.
- fixes a bug where temporary timers would crash. Thanks to @holykol for finding and fixing the issue.

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
