defmodule EcspanseTest do
  use ExUnit.Case

  defmodule TestStartupEvent do
    @moduledoc false
    use Ecspanse.Event, fields: [:data, :pid]
  end

  defmodule TestStartupSystem do
    @moduledoc false
    use Ecspanse.System,
      events_subscription: [TestStartupEvent]

    @impl true
    def run(%TestStartupEvent{} = event, _frame) do
      send(event.pid, {:startup, event.data})
    end
  end

  defmodule TestRunningSystem do
    @moduledoc false
    use Ecspanse.System,
      events_subscription: [TestStartupEvent]

    @impl true
    def run(%TestStartupEvent{} = event, _frame) do
      # this should never happen
      # the TestStartupEvent should run only on startup
      send(event.pid, {:running, event.data})
    end
  end

  defmodule TestWorld do
    @moduledoc false
    use Ecspanse.World

    @impl true
    def setup(world) do
      world
      |> Ecspanse.World.add_startup_system(TestStartupSystem)
      |> Ecspanse.World.add_frame_start_system(TestRunningSystem)
    end
  end

  describe "new/2" do
    test "creates a new world" do
      assert {:ok, _token} = Ecspanse.new(TestWorld)
      assert {:ok, token} = Ecspanse.new(TestWorld, name: TestName)

      token_payload = Ecspanse.Util.decode_token(token)
      assert token_payload.world_name == TestName
    end

    test "can inject events at startup" do
      assert {:ok, _token} =
               Ecspanse.new(TestWorld,
                 startup_events: [{TestStartupEvent, data: 123, pid: self()}]
               )

      assert_receive {:startup, 123}
      refute_receive {:running, _}
    end
  end
end
