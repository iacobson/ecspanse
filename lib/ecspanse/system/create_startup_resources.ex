defmodule Ecspanse.System.CreateStartupResources do
  @moduledoc """
  Special framework system that creates default resources.
  Automatically runs only once on startup.
  """

  use Ecspanse.System

  @impl true
  def run(_frame) do
    Ecspanse.Command.insert_resource!(Ecspanse.Resource.State)
    Ecspanse.Command.insert_resource!(Ecspanse.Resource.FPS)

    state = Ecspanse.Server.debug()
    startup_resource_configs = state.startup_resources

    for resource_config <- startup_resource_configs do
      Ecspanse.Command.insert_resource!(resource_config)
    end
  end
end
