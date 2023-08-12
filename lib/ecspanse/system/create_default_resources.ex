defmodule Ecspanse.System.CreateDefaultResources do
  @moduledoc """
  Special framework system that creates default resources.
  Automatically runs only once on startup.
  """

  use Ecspanse.System

  @impl true
  def run(_frame) do
    Ecspanse.Command.insert_resource!(Ecspanse.Resource.State)
    Ecspanse.Command.insert_resource!(Ecspanse.Resource.FPS)
  end
end
