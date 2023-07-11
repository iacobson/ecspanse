defmodule Ecspanse.Event.ResourceUpdated do
  @moduledoc """
  TODO
  Special framework event triggered when a new resource is updated.
  Contains the resource state struct after the update.
  """
  use Ecspanse.Event, fields: [:resource]

  @type t :: %__MODULE__{
          resource: struct()
        }
end
