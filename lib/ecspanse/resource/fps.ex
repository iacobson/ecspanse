defmodule Ecspanse.Resource.FPS do
  @moduledoc """
  A special resource provided by the framework to check the FPS in real-time.
  The framework also provides a special system that updates the FPS resource.
  The TrackFPS system needs to be added to the Server, in order to calculate the FPS.

  - value: the last second FPS value
  - current: the current frames accumulated this second
  - millisecond: the current millisecond of the second

  A special resource provided by the framework for real-time FPS monitoring.
  The framework also includes a dedicated system that updates this FPS resource.
  To enable FPS calculation, the `Ecspanse.System.TrackFPS` system must be added
  to the `c:Ecspanse.setup/1` as a sync system.

  The FPS state fields are:

  - `:value` - the previous second's FPS value.
  - `:current` - the number of frames within the current second.
  - `:millisecond` - the current millisecond within the second.
  """
  use Ecspanse.Resource,
    state: [value: 0, current: 0, millisecond: 0]

  alias __MODULE__

  @type t :: %__MODULE__{
          value: non_neg_integer(),
          current: non_neg_integer(),
          millisecond: non_neg_integer()
        }

  @impl Ecspanse.Resource
  def validate(%FPS{value: value, current: current, millisecond: millisecond}) do
    if is_integer(value) and value >= 0 and
         (is_integer(current) and current >= 0) and
         (is_integer(millisecond) and millisecond >= 0) do
      :ok
    else
      {:error,
       "Invalid state value. The Resource.FPS value, current and millisecond must be non neg integers"}
    end
  end
end
