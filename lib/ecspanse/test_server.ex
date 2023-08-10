defmodule Ecspanse.TestServer do
  @moduledoc """
  TODO put here info about testing. How you start a test server, how you upgrade a process to a system, etc.
  Instead of Ecspanse.Server this will start when the application starts in test env.
  This is needed just not to crash the tests when they start the app.
  """

  use GenServer

  @doc false
  def start_link(payload) do
    GenServer.start_link(__MODULE__, payload)
  end

  @doc false
  def init(_payload) do
    {:ok, nil}
  end
end
