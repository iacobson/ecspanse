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

  ###

  setup do
    on_exit(fn ->
      :timer.sleep(5)

      case Process.whereis(Ecspanse.World) do
        pid when is_pid(pid) ->
          Process.exit(pid, :normal)

        _ ->
          nil
      end
    end)

    :ok
  end

  describe "new/2" do
    test "creates a new world" do
      assert :ok = Ecspanse.new(TestWorld)
    end

    test "can inject events at startup" do
      assert :ok =
               Ecspanse.new(TestWorld,
                 startup_events: [{TestStartupEvent, data: 123, pid: self()}]
               )

      assert_receive {:startup, 123}
      refute_receive {:running, _}
    end
  end

  describe "fetch_world_process/1" do
    test "fetches the world process" do
      assert :ok = Ecspanse.new(TestWorld, name: TestName)
      assert {:ok, pid} = Ecspanse.fetch_world_process()
      assert Process.alive?(pid)
    end
  end

  describe "event/3" do
    test "queues an event for the next frame" do
      assert :ok = Ecspanse.new(TestWorld, name: TestName, test: true)
      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, state}
      assert state.frame_data.event_batches == []
      Ecspanse.event(TestCustomEvent)
      assert_receive {:next_frame, state}
      assert [[%EcspanseTest.TestCustomEvent{}]] = state.frame_data.event_batches
    end

    test "groups in individual batches an event without a batch key, queued multiple times in the same frame" do
      assert :ok = Ecspanse.new(TestWorld, name: TestName, test: true)
      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, state}
      assert state.frame_data.event_batches == []
      Ecspanse.event(TestCustomEvent)
      Ecspanse.event(TestCustomEvent)
      assert_receive {:next_frame, state}

      assert [[%EcspanseTest.TestCustomEvent{}], [%EcspanseTest.TestCustomEvent{}]] =
               state.frame_data.event_batches
    end

    test "providing unique batch keys, groups the events in the same batch for parallel processing" do
      assert :ok = Ecspanse.new(TestWorld, name: TestName, test: true)
      entity_1 = Ecspanse.Entity.build(UUID.uuid4())
      entity_2 = Ecspanse.Entity.build(UUID.uuid4())

      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, state}
      assert state.frame_data.event_batches == []

      Ecspanse.event(TestCustomEvent, batch_key: entity_1.id)
      Ecspanse.event(TestCustomEvent, batch_key: entity_2.id)
      Ecspanse.event(TestCustomEvent, batch_key: entity_1.id)
      assert_receive {:next_frame, state}

      assert [
               [%EcspanseTest.TestCustomEvent{}, %EcspanseTest.TestCustomEvent{}],
               [%EcspanseTest.TestCustomEvent{}]
             ] = state.frame_data.event_batches
    end
  end
end
