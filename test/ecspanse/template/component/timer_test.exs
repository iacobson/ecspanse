defmodule Ecspanse.Template.Component.TimerTest do
  use ExUnit.Case

  defmodule ParentProcessTestResource do
    @moduledoc false
    use Ecspanse.Resource, state: [:pid]
  end

  defmodule TimerTestEvent do
    @moduledoc false
    use Ecspanse.Template.Event.Timer
  end

  defmodule RepeatTimerTestComponent do
    @moduledoc false
    use Ecspanse.Template.Component.Timer,
      state: [duration: 2, time: 2, event: TimerTestEvent, mode: :repeat, paused: false]
  end

  defmodule OnceTimerTestComponent do
    @moduledoc false
    use Ecspanse.Template.Component.Timer,
      state: [duration: 2, time: 2, event: TimerTestEvent, mode: :once, paused: false]
  end

  defmodule TemporaryTimerTestComponent do
    @moduledoc false
    use Ecspanse.Template.Component.Timer,
      state: [duration: 2, time: 2, event: TimerTestEvent, mode: :temporary, paused: false]
  end

  defmodule TestSystem do
    @moduledoc false
    use Ecspanse.System,
      event_subscriptions: [TimerTestEvent]

    @impl true
    def run(%TimerTestEvent{}, _frame) do
      {:ok, %ParentProcessTestResource{pid: pid}} = fetch_resource(ParentProcessTestResource)
      send(pid, :time_up)
    end
  end

  defmodule TestServer do
    @moduledoc false
    use Ecspanse

    @impl true
    def setup(data) do
      data
      |> add_system(TestSystem)
      |> add_frame_end_system(Ecspanse.System.Timer)
    end
  end

  setup do
    start_supervised({TestServer, :test})
    Ecspanse.Server.test_server(self())
    # simulate commands are run from a System
    Ecspanse.System.debug()

    Ecspanse.Command.insert_resource!({ParentProcessTestResource, pid: self()})

    :ok
  end

  describe "repeat timer" do
    test "the event is triggered repeatedly" do
      entity =
        Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [RepeatTimerTestComponent]})

      assert_receive {:next_frame, _state}

      assert_receive :time_up
      assert_receive :time_up
      assert_receive :time_up

      assert {:ok, _timer_component} = RepeatTimerTestComponent.fetch(entity)
    end
  end

  describe "once timer" do
    test "the event is triggered once but the timer component is present" do
      entity =
        Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [OnceTimerTestComponent]})

      assert_receive {:next_frame, _state}
      assert_receive :time_up

      assert_receive {:next_frame, _state}
      refute_receive :time_up

      assert {:ok, _timer_component} = OnceTimerTestComponent.fetch(entity)
    end
  end

  describe "temporary timer" do
    test "the event is triggered once and the timer component is removed" do
      entity =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TemporaryTimerTestComponent]}
        )

      assert_receive {:next_frame, _state}
      assert_receive :time_up

      assert_receive {:next_frame, _state}
      refute_receive :time_up

      assert {:error, :not_found} = TemporaryTimerTestComponent.fetch(entity)
    end
  end
end
