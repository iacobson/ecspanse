defmodule Ecspanse.SystemTest do
  alias Ecspanse.WorldTest.TestResource1
  use ExUnit.Case

  defmodule TestComponent1 do
    @moduledoc false
    use Ecspanse.Component, state: [value: :foo]
  end

  defmodule TestComponent2 do
    @moduledoc false
    use Ecspanse.Component, access_mode: :readonly
  end

  defmodule TestResource1 do
    @moduledoc false
    use Ecspanse.Resource, state: [value: :foo]
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

  defmodule TestSystem2 do
    @moduledoc false
    use Ecspanse.System,
      events_subscription: [
        Ecspanse.Event.ComponentCreated,
        Ecspanse.Event.ComponentDeleted,
        Ecspanse.Event.ComponentUpdated,
        Ecspanse.Event.ResourceCreated,
        Ecspanse.Event.ResourceDeleted,
        Ecspanse.Event.ResourceUpdated
      ]

    def run(event, frame) do
      test_pid = Ecspanse.World.debug(frame.token).test_pid

      case event do
        %Ecspanse.Event.ComponentCreated{component: %TestComponent1{} = component} ->
          send(test_pid, {:component_created, component})

        %Ecspanse.Event.ComponentDeleted{component: %TestComponent1{} = component} ->
          send(test_pid, {:component_deleted, component})

        %Ecspanse.Event.ComponentUpdated{component: %TestComponent1{} = component} ->
          send(test_pid, {:component_updated, component})

        %Ecspanse.Event.ResourceCreated{resource: %TestResource1{} = resource} ->
          send(test_pid, {:resource_created, resource})

        %Ecspanse.Event.ResourceDeleted{resource: %TestResource1{} = resource} ->
          send(test_pid, {:resource_deleted, resource})

        %Ecspanse.Event.ResourceUpdated{resource: %TestResource1{} = resource} ->
          send(test_pid, {:resource_updated, resource})

        _ ->
          :ok
      end
    end
  end

  defmodule TestWorld1 do
    @moduledoc false
    use Ecspanse.World

    def setup(world) do
      world
      |> Ecspanse.World.add_system(TestSystem1)
      |> Ecspanse.World.add_system(TestSystem2)
    end
  end

  describe "component locking" do
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
  end

  describe "systems with events subscription" do
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

  describe "command generated events" do
    test "component_created event on component creation" do
      assert {:ok, token} = Ecspanse.new(TestWorld1, name: TestName1, test: true)
      Ecspanse.System.debug(token)
      entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})
      :timer.sleep(20)
      assert_receive {:next_frame, _state}

      assert_received {:component_created, created_component}

      {:ok, component} = Ecspanse.Query.fetch_component(entity, TestComponent1, token)

      assert created_component == component
    end

    test "component_deleted event on component deletion" do
      assert {:ok, token} = Ecspanse.new(TestWorld1, name: TestName1, test: true)
      Ecspanse.System.debug(token)
      entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      {:ok, component} = Ecspanse.Query.fetch_component(entity, TestComponent1, token)

      Ecspanse.Command.remove_component!(component)
      :timer.sleep(20)
      assert_receive {:next_frame, _state}

      assert_received {:component_deleted, deleted_component}

      assert deleted_component == component
    end

    test "component_updated event on component update" do
      assert {:ok, token} = Ecspanse.new(TestWorld1, name: TestName1, test: true)
      Ecspanse.System.debug(token)
      entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})
      {:ok, component} = Ecspanse.Query.fetch_component(entity, TestComponent1, token)
      Ecspanse.Command.update_component!(component, value: :bar)
      :timer.sleep(20)
      assert_receive {:next_frame, _state}

      assert_received {:component_updated, updated_component}
      {:ok, component} = Ecspanse.Query.fetch_component(entity, TestComponent1, token)

      assert updated_component == component
    end

    test "resource_created event on resource creation" do
      assert {:ok, token} = Ecspanse.new(TestWorld1, name: TestName1, test: true)
      Ecspanse.System.debug(token)
      resource = Ecspanse.Command.insert_resource!(TestResource1)
      :timer.sleep(20)
      assert_receive {:next_frame, _state}

      assert_received {:resource_created, created_resource}

      assert created_resource == resource
    end

    test "resource_deleted event on resource deletion" do
      assert {:ok, token} = Ecspanse.new(TestWorld1, name: TestName1, test: true)
      Ecspanse.System.debug(token)
      resource = Ecspanse.Command.insert_resource!(TestResource1)
      resource = Ecspanse.Command.delete_resource!(resource)
      :timer.sleep(20)
      assert_receive {:next_frame, _state}

      assert_received {:resource_deleted, deleted_resource}

      assert deleted_resource == resource
    end

    test "resource_updated event on resource update" do
      assert {:ok, token} = Ecspanse.new(TestWorld1, name: TestName1, test: true)
      Ecspanse.System.debug(token)
      resource = Ecspanse.Command.insert_resource!(TestResource1)
      resource = Ecspanse.Command.update_resource!(resource, value: :bar)
      :timer.sleep(20)
      assert_receive {:next_frame, _state}

      assert_received {:resource_updated, updated_resource}

      assert updated_resource == resource
    end
  end
end
