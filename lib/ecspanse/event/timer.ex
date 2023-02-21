defmodule Ecspanse.Event.Timer do
  @moduledoc """
  TODO
  A special event provided by the framework to handle Timer events.

  The event that will be dispatched when the timer reaches 0.
    - it takes no options
    - the state is %MyTimerEvent{entity: entity}. The entity is the owner of the Timer compoenent.
    - the event key is set to the id of the owner entity.


  Example:
    defmodule MyTimerEvent do
      use Ecspanse.Event.Timer
    end
  """
  defmacro __using__(_opts) do
    quote do
      use Ecspanse.Event, fields: [:entity]
    end
  end
end
