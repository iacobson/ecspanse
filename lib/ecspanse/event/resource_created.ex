defmodule Ecspanse.Event.ResourceCreated do
  @moduledoc """
  TODO
  Special framework event triggered when a new resource is created.
  Contains the resource state struct.
  """
  use Ecspanse.Event, fields: [:resource]

  @type t :: %__MODULE__{
          resource: struct()
        }
end
