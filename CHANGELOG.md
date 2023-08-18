# Changelog

## v0.2.0 (2023-08-18)

### Breaking

- `use Ecspanse.Component.Timer` and `use Ecspanse.Event.Timer` are now deprecated.
  Use `use Ecspanse.Template.Component.Timer` and `use Ecspanse.Template.Event.Timer` instead.

### Features

- introducing `Ecspanse.Template.Component` and `Ecspanse.Template.Event` to simplify the creation of related components and events.
- add new function `Ecspanse.Query.fetch_component/2` to fetch a system's component by a list of tags.

## v0.1.2 (2023-08-14)

### Fixes

- remove unneeded dependency `plug_crypto`
- upgrade dependencies: `credo`, `ex_doc`, `jason`

## v0.1.1 (2023-08-12)

### Fixes

- adds the missing project `:package`
