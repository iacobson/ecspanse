defmodule Ecspanse.System.TrackFPS do
  @moduledoc """
  # TODO
  Special System provided by the framework to track the FPS.
  The value is stored in the Ecspanse.Resource.FPS resource.
  """
  use Ecspanse.System

  @impl true
  def run(frame) do
    {:ok, fps_resource} = Ecspanse.Query.fetch_resource(Ecspanse.Resource.FPS, frame.token)
    new_time = fps_resource.millisecond + frame.delta

    updated_resource =
      if new_time >= 1000 do
        [value: fps_resource.current + 1, current: 0, millisecond: new_time - 1000]
      else
        [current: fps_resource.current + 1, millisecond: new_time]
      end

    Ecspanse.Command.update_resource!(fps_resource, updated_resource)
  end
end
