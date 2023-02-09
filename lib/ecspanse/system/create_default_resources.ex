defmodule Ecspanse.System.CreateDefaultResources do
  @moduledoc false
  # Special framework system that creates default resources.
  # Runs only once, when the system is started.
  use Ecspanse.System

  @impl true
  def run(_frame) do
    Ecspanse.Command.insert_resource!(Ecspanse.Resource.State)
    Ecspanse.Command.insert_resource!(Ecspanse.Resource.FPS)
  end
end
