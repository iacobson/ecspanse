defmodule Ecspanse.Event.ComponentCreated do
  @moduledoc """
  Special framework event triggered automatically
  when a new component is created.
  Contains the component state struct.

  See [a working example](./tutorial.md#finding-resources) in the tutorial
  """
  use Ecspanse.Event, fields: [:component]

  @type t :: %__MODULE__{
          component: struct()
        }
end
