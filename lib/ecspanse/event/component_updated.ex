defmodule Ecspanse.Event.ComponentUpdated do
  @moduledoc """
  TODO
  Special framework event triggered when a new component is updated.
  Contains the component state after the update.
  """
  use Ecspanse.Event, fields: [:component]

  @type t :: %__MODULE__{
          component: struct()
        }
end
