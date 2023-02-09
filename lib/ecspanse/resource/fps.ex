defmodule Ecspanse.Resource.FPS do
  @moduledoc """
  # TODO
  A special resource provided by the framework to check the FPS in real-time.
  The framework also provides a special system that updates the FPS resource.
  The TrackFPS system needs to be added to the World, in order to calculate the FPS.

  """
  use Ecspanse.Resource,
    state: [value: 0, current: 0, millisecond: 0]

  alias __MODULE__

  @type t :: %__MODULE__{
          value: non_neg_integer(),
          current: non_neg_integer(),
          millisecond: non_neg_integer()
        }

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
