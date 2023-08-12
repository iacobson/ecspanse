defmodule Ecspanse.Event.Timer do
  @moduledoc """
  TODO
  A special event provided by the framework to handle Timer events.

  This is a **Utility Event**.

  The event that will be dispatched when the timer reaches 0.
    - it takes no options
    - the state is %MyTimerEvent{entity_id: entity_id}. The entity is the owner of the Timer compoenent.
    - the event key is set to the id of the owner entity.


  Example:
    defmodule MyTimerEvent do
      use Ecspanse.Event.Timer
    end
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
