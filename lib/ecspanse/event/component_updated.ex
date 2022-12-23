defmodule Ecspanse.Event.ComponentUpdated do
  @moduledoc """
  TODO
  Special framework event triggered when a new component is updated.
  Contains the component state struct before and after the update.
  """
  use Ecspanse.Event, fields: [:initial, :final]

  @type t :: %__MODULE__{
          initial: component :: struct(),
          final: component :: struct()
        }
end
