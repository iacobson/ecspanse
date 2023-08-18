defmodule Ecspanse.Template.Event.Timer do
  @moduledoc """
  The `Timer` is a **Template Event** designed to facilitate the creation
  of custom timer (countdown) events.

  It serves as a foundation for building custom timer events with `use Ecspanse.Template.Event.Timer`.
  It takes no options.

  The event that will be dispatched by `Event.System.Timer` system when
  the timer component reaches 0.

  Their state is predefined to `%CustomEventModule{entity_id: entity_id}`,
  where entity refers to owner of the custom timer component.

  ## Example:
    ```elixir
    defmodule EnergyRestoreTimer do
      use Ecspanse.Template.Event.Timer
    end
    ```

  See `Ecspanse.Template.Component.Timer` for more details.
  """
  use Ecspanse.Template.Event, fields: [:entity_id]
end
