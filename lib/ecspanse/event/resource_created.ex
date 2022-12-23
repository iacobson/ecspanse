defmodule Ecspanse.Event.ResourceCreated do
  @moduledoc """
  TODO
  Special framework event triggered when a new resource is created.
  Contains the resource state struct.
  """
  use Ecspanse.Event, fields: [:created]

  @type t :: %__MODULE__{
          created: resource :: struct()
        }
end
