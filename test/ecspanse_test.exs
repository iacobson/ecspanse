defmodule EcspanseTest do
  use ExUnit.Case

  defmodule TestStartupEvent do
    @moduledoc false
    use Ecspanse.Event, fields: [:data, :pid]
  end

  defmodule TestCustomEvent do
    @moduledoc false
    use Ecspanse.Event
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
    use Ecspanse.World, fps_limit: 60

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

  describe "terminate/1" do
    test "terminates the world" do
      assert {:ok, token} = Ecspanse.new(TestWorld)
      assert {:ok, _} = Ecspanse.fetch_world_process(token)
      assert Ecspanse.terminate(token) == :ok

      # wait for the world GenServer `terminate/2` callback to finish
      :timer.sleep(100)
      assert {:error, :not_found} = Ecspanse.fetch_world_process(token)
    end
  end

  describe "fetch_token/1" do
    test "fetches the world token from the world name" do
      assert {:ok, token} = Ecspanse.new(TestWorld, name: TestName)
      assert {:ok, found_token} = Ecspanse.fetch_token(TestName)
      assert token == found_token
    end
  end

  describe "fetch_world_process/1" do
    test "fetches the world process from the world token" do
      assert {:ok, token} = Ecspanse.new(TestWorld, name: TestName)
      assert {:ok, %{name: name, pid: pid}} = Ecspanse.fetch_world_process(token)
      assert name == TestName
      assert Process.alive?(pid)
    end
  end

  describe "event/3" do
    test "queues an event for the next frame" do
      assert {:ok, token} = Ecspanse.new(TestWorld, name: TestName, test: true)
      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, state}
      assert state.frame_data.event_batches == []
      Ecspanse.event(TestCustomEvent, token)
      assert_receive {:next_frame, state}
      assert [[%EcspanseTest.TestCustomEvent{}]] = state.frame_data.event_batches
    end

    test "groups in individual batches an event without a batch key, queued multiple times in the same frame" do
      assert {:ok, token} = Ecspanse.new(TestWorld, name: TestName, test: true)
      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, state}
      assert state.frame_data.event_batches == []
      Ecspanse.event(TestCustomEvent, token)
      Ecspanse.event(TestCustomEvent, token)
      assert_receive {:next_frame, state}

      assert [[%EcspanseTest.TestCustomEvent{}], [%EcspanseTest.TestCustomEvent{}]] =
               state.frame_data.event_batches
    end

    test "providing unique batch keys, groups the events in the same batch for parallel processing" do
      assert {:ok, token} = Ecspanse.new(TestWorld, name: TestName, test: true)
      entity_1 = Ecspanse.Entity.build(UUID.uuid4())
      entity_2 = Ecspanse.Entity.build(UUID.uuid4())

      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, state}
      assert state.frame_data.event_batches == []

      Ecspanse.event(TestCustomEvent, token, batch_key: entity_1.id)
      Ecspanse.event(TestCustomEvent, token, batch_key: entity_2.id)
      Ecspanse.event(TestCustomEvent, token, batch_key: entity_1.id)
      assert_receive {:next_frame, state}

      assert [
               [%EcspanseTest.TestCustomEvent{}, %EcspanseTest.TestCustomEvent{}],
               [%EcspanseTest.TestCustomEvent{}]
             ] = state.frame_data.event_batches
    end
  end
end
