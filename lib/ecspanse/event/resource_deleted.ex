defmodule Ecspanse.Event.ResourceDeleted do
  @moduledoc """
  Special framework event triggered automatically
   when a new resource is deleted.
  Contains the deleted resource state struct.
  """
  use Ecspanse.Event, fields: [:resource]

  @type t :: %__MODULE__{
          resource: struct()
        }
end
