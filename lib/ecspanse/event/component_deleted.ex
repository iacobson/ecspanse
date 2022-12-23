defmodule Ecspanse.Event.ComponentDeleted do
  @moduledoc """
  TODO
  Special framework event triggered when a new component is deleted.
  Contains the deleted component state struct.
  """
  use Ecspanse.Event, fields: [:deleted]

  @type t :: %__MODULE__{
          deleted: component :: struct()
        }
end
