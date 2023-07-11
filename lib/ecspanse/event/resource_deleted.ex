defmodule Ecspanse.Event.ResourceDeleted do
  @moduledoc """
  TODO
  Special framework event triggered when a new resource is deleted.
  Contains the deleted resource state struct.
  """
  use Ecspanse.Event, fields: [:resource]

  @type t :: %__MODULE__{
          resource: struct()
        }
end
