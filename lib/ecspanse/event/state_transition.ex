defmodule Ecspanse.Event.StateTransition do
  @moduledoc """
  Special library event emitted upon a state change.
  """

  use Ecspanse.Event, fields: [:module, :previous_state, :current_state]

  @type t :: %__MODULE__{
          module: module(),
          previous_state: atom(),
          current_state: atom()
        }
end
