defmodule Ecspanse.SystemTest do
  alias Ecspanse.WorldTest.TestEvent1
  use ExUnit.Case

  defmodule TestComponent1 do
    @moduledoc false
    use Ecspanse.Component, state: [value: :foo]
  end

  defmodule TestComponent2 do
    @moduledoc false
    use Ecspanse.Component, access_mode: :readonly
  end

  defmodule TestEvent1 do
    @moduledoc false
    use Ecspanse.Event, fields: [value: :bar, entity: nil]
  end

  defmodule TestEvent2 do
    @moduledoc false
    use Ecspanse.Event, fields: [value: :baz, entity: nil]
  end

  defmodule TestSystem1 do
    @moduledoc false
    use Ecspanse.System,
      lock_components: [TestComponent1, TestComponent2],
      events_subscription: [TestEvent1]

    def run(%TestEvent1{value: value, entity: entity}, frame) do
      {:ok, test_component_1} =
        Ecspanse.Query.fetch_component(entity, TestComponent1, frame.token)

      Ecspanse.Command.update_component!(test_component_1, value: value)

      Ecspanse.Command.add_component!(entity, TestComponent2)
      test_pid = Ecspanse.World.debug(frame.token).test_pid

      send(test_pid, :test_event_1)
    end
  end

  defmodule TestWorld1 do
    @moduledoc false
    use Ecspanse.World

    def setup(world) do
      world
      |> Ecspanse.World.add_system(TestSystem1)
    end
  end

  test "when running an async system all the components that may be added, removed or updated must be locked" do
    assert {:ok, token} = Ecspanse.new(TestWorld1, name: TestName1, test: true)

    Ecspanse.System.debug(token)

    entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

    assert {:ok, component_1} = Ecspanse.Query.fetch_component(entity, TestComponent1, token)
    assert component_1.value == :foo

    assert {:error, :not_found} = Ecspanse.Query.fetch_component(entity, TestComponent2, token)

    assert_receive {:next_frame, _state}

    Ecspanse.event({TestEvent1, value: :bar, entity: entity}, token)

    assert_receive {:next_frame, _state}

    assert_receive :test_event_1
    :timer.sleep(20)
    assert_receive {:next_frame, _state}

    assert {:ok, component_1} = Ecspanse.Query.fetch_component(entity, TestComponent1, token)
    assert component_1.value == :bar
    assert {:ok, _component_2} = Ecspanse.Query.fetch_component(entity, TestComponent2, token)
  end

  test "systems with events subscription run only for the subscribed events" do
    assert {:ok, token} = Ecspanse.new(TestWorld1, name: TestName1, test: true)

    Ecspanse.System.debug(token)

    entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

    assert {:ok, component_1} = Ecspanse.Query.fetch_component(entity, TestComponent1, token)
    assert component_1.value == :foo

    assert_receive {:next_frame, _state}

    Ecspanse.event({TestEvent2, value: :baz, entity: entity}, token)

    assert_receive {:next_frame, _state}

    refute_receive :test_event_1
    :timer.sleep(20)
    assert_receive {:next_frame, _state}

    assert {:ok, component_1} = Ecspanse.Query.fetch_component(entity, TestComponent1, token)
    assert component_1.value == :foo
  end
end
