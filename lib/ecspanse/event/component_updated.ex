defmodule Ecspanse.Event.ComponentUpdated do
  @moduledoc """
  TODO
  Special framework event triggered when a new component is updated.
  Contains the component state struct before and after the update.
  """
  use Ecspanse.Event, fields: [:updated]

  @type t :: %__MODULE__{
          updated: component :: struct()
        }
end
