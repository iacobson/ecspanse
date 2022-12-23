defmodule Ecspanse.Event.ResourceDeleted do
  @moduledoc """
  TODO
  Special framework event triggered when a new resource is deleted.
  Contains the deleted resource state struct.
  """
  use Ecspanse.Event, fields: [:deleted]

  @type t :: %__MODULE__{
          deleted: resource :: struct()
        }
end
