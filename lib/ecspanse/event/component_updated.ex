defmodule Ecspanse.Event.ComponentUpdated do
  @moduledoc """
  Special framework event triggered automatically
  when a new component is updated.
  Contains the component state after the update.

  See [a working example](./tutorial.md#finding-resources) in the tutorial
  """
  use Ecspanse.Event, fields: [:component]

  @type t :: %__MODULE__{
          component: struct()
        }
end
