defmodule Ecspanse.Event.ComponentCreated do
  @moduledoc """
  TODO
  Special framework event triggered when a new component is created.
  Contains the component state struct.

  See example in the tutorial
  """
  use Ecspanse.Event, fields: [:component]

  @type t :: %__MODULE__{
          component: struct()
        }
end
