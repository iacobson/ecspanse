defmodule Ecspanse.Event.ResourceUpdated do
  @moduledoc """
  Special framework event triggered automatically
  when a new resource is updated.
  Contains the resource state struct after the update.
  """
  use Ecspanse.Event, fields: [:resource]

  @type t :: %__MODULE__{
          resource: struct()
        }
end
