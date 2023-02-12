defmodule Ecspanse.Event.ResourceUpdated do
  @moduledoc """
  TODO
  Special framework event triggered when a new resource is updated.
  Contains the resource state struct before and after the update.
  """
  use Ecspanse.Event, fields: [:updated]

  @type t :: %__MODULE__{
          updated: resource :: struct()
        }
end
