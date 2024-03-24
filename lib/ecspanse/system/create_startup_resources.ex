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

    server_state = Ecspanse.Server.debug()
    state_specs = server_state.startup_states
    startup_resource_specs = server_state.startup_resources

    for state_spec <- state_specs do
      case state_spec do
        {state_module, initial_state} when is_atom(state_module) and is_atom(initial_state) ->
          Ecspanse.Command.insert_resource!({state_module, [current: initial_state]})

        state_module when is_atom(state_module) ->
          Ecspanse.Command.insert_resource!(state_module)
      end
    end

    for resource_spec <- startup_resource_specs do
      Ecspanse.Command.insert_resource!(resource_spec)
    end
  end
end
