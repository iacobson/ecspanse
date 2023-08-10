defmodule Ecspanse.Frame do
  @moduledoc """
  The frame is a struct that encapsulates the state of the current frame.

  It holds information such as the time elapsed since the last frame and any batches of events that have been inserted during the previous frame.
  This frame struct is available to all systems during the frame.

  ## Fields

  - `:event_batches` - a collection of event batches queued for execution within this frame.
  - `:delta` - the time elapsed since the last frame in milliseconds.
  """

  @typedoc """
  The frame struct.

  ## Example

    ```elixir
    %Ecspanse.Frame{
      event_batches: [[%Demo.Events.MoveHero{direction: :left}, %Demo.Events.FindResource{type: :gold}], [%Demo.Events.MoveHero{direction: :down}]],
      delta: 18,
    }
    ```

  """
  @type t :: %__MODULE__{
          event_batches: list(list(event :: struct())),
          delta: non_neg_integer()
        }

  defstruct event_batches: [], delta: 0
end
