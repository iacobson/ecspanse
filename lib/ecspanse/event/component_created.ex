defmodule Ecspanse.Event.ComponentCreated do
  @moduledoc """
  TODO
  Special framework event triggered when a new component is created.
  Contains the component state struct.
  """
  use Ecspanse.Event, fields: [:created]

  @type t :: %__MODULE__{
          created: component :: struct()
        }
end
