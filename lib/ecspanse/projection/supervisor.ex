defmodule Ecspanse.Projection.Supervisor do
  @moduledoc false
  # The projection supervisor spawns new termporary Projection servers.

  use DynamicSupervisor

  def child_spec(%{name: name}) do
    %{
      id: name,
      start: {__MODULE__, :start_link, [name]},
      restart: :temporary,
      type: :supervisor
    }
  end

  # API

  def start_link do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  # SERVER

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
