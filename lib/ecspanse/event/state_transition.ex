defmodule Ecspanse.Event.StateTransition do
  @moduledoc """
  Special library event emitted upon a state change.

  ## Examples

    ```elixir
    %Ecspanse.Event.StateTransition{
      module: Demo.States.Game,
      previous_state: :running,
      current_state: :paused
    }
    ```
  """

  use Ecspanse.Event, fields: [:module, :previous_state, :current_state]

  @type t :: %__MODULE__{
          module: module(),
          previous_state: atom(),
          current_state: atom()
        }
end
