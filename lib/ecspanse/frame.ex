defmodule Ecspanse.Frame do
  @moduledoc """
  A struct that represents the current frame in the world.

  It contains information about the elapsed time since the last frame, as well as any event batches that were generated during the frame.
  The Frame struct is passed to all systems during the frame.

  ## Structs

  - `Frame` - a struct that represents a single frame in the world.

  ## Fields

  - `event_batches` - a list of event batches to be executed during the frame.
  - `delta` - the time elapsed since the last frame in milliseconds.

  """

  @type t :: %__MODULE__{
          event_batches: list(list(Ecspanse.Event.t())),
          delta: non_neg_integer()
        }

  defstruct event_batches: [], delta: 0
end
