defmodule Ecspanse.TestServer do
  @moduledoc """
  This server is initiated upon application launch when operating in the test environment.
  This is done to allow tests to start their own custom servers and schedule custom systems.

  A basic test system setup may look like this:
    ```elixir
    defmodule Demo.Systems.MoveHeroTest do
      use ExUnit.Case

      defmodule DemoTest do
        @moduledoc "A setup that does not schedule any system"
        use Ecspanse

        @impl true
        def setup(data) do
          data
        end
      end

      setup do
        {:ok, _pid} = start_supervised({DemoTest, :test})
        Ecspanse.System.debug()
      end
    end
    ```

    In the test `setup` block, the server is started with the tuple `{DemoTest, :test}`.
    This is needed to point Ecspanse to start the `Ecspanse.Server` with the `DemoTest` setup.

    The `Ecspanse.System.debug/0` call grants the test pid `Ecspanse.System` powers.
    Meaning that it can runt commands without being in the context of a system.
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
