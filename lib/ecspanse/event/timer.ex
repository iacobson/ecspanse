defmodule Ecspanse.Event.Timer do
  @moduledoc """
  The `Timer` is a **Utility Event** designed to facilitate the creation
  of custom timer (countdown) events.

  Instead of using this event directly, it serves as a foundation
  for building custom timer events with `use Ecspanse.Event.Timer`.
  It takes no options.

  The event that will be dispatched by `Event.System.Timer` system when
  the timer component reaches 0.

  Their state is predefined to `%CustomEventModule{entity_id: entity_id}`,
  where entity refers to owner of the custom timer component.

  ## Example:
    ```elixir
    defmodule MyTimerEvent do
      use Ecspanse.Event.Timer
    end
    ```

  See `Ecspanse.Component.Timer` for more details.
  """
  defmacro __using__(_opts) do
    quote do
      use Ecspanse.Event, fields: [:entity_id]

      @type t :: %__MODULE__{
              entity_id: Ecspanse.Entity.id()
            }
    end
  end
end
