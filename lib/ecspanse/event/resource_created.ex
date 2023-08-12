defmodule Ecspanse.Event.ResourceCreated do
  @moduledoc """
  Special framework event triggered automatically
  when a new resource is created.
  Contains the resource state struct.
  """
  use Ecspanse.Event, fields: [:resource]

  @type t :: %__MODULE__{
          resource: struct()
        }
end
