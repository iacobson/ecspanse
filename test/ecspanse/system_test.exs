defmodule Ecspanse.SystemTest do
  use ExUnit.Case

  defmodule TestComponent1 do
    @moduledoc false
    use Ecspanse.Component, state: [value: :foo]
  end

  defmodule TestComponent2 do
    @moduledoc false
    use Ecspanse.Component
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

    def run(%TestEvent1{value: value, entity: entity}, _frame) do
      {:ok, test_component_1} =
        Ecspanse.Query.fetch_component(entity, TestComponent1)

      Ecspanse.Command.update_component!(test_component_1, value: value)

      Ecspanse.Command.add_component!(entity, TestComponent2)
      test_pid = Ecspanse.Server.debug().test_pid

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

    def run(event, _frame) do
      test_pid = Ecspanse.Server.debug().test_pid

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

  defmodule TestServer1 do
    @moduledoc false
    use Ecspanse

    def setup(data) do
      data
      |> Ecspanse.add_system(TestSystem1)
      |> Ecspanse.add_system(TestSystem2)
    end
  end

  ###

  setup do
    start_supervised({TestServer1, :test})
    Ecspanse.Server.test_server(self())

    # simulate commands are run from a System
    Ecspanse.System.debug()

    :ok
  end

  describe "component locking" do
    test "when running an async system all the components that may be added, removed or updated must be locked" do
      entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert {:ok, component_1} = Ecspanse.Query.fetch_component(entity, TestComponent1)
      assert component_1.value == :foo

      assert {:error, :not_found} = Ecspanse.Query.fetch_component(entity, TestComponent2)

      assert_receive {:next_frame, _state}

      Ecspanse.event({TestEvent1, value: :bar, entity: entity})

      assert_receive {:next_frame, _state}

      assert_receive :test_event_1
      :timer.sleep(20)
      assert_receive {:next_frame, _state}

      assert {:ok, component_1} = Ecspanse.Query.fetch_component(entity, TestComponent1)
      assert component_1.value == :bar
      assert {:ok, _component_2} = Ecspanse.Query.fetch_component(entity, TestComponent2)
    end
  end

  describe "systems with events subscription" do
    test "systems with events subscription run only for the subscribed events" do
      entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert {:ok, component_1} = Ecspanse.Query.fetch_component(entity, TestComponent1)
      assert component_1.value == :foo

      assert_receive {:next_frame, _state}

      Ecspanse.event({TestEvent2, value: :baz, entity: entity})

      assert_receive {:next_frame, _state}

      refute_receive :test_event_1
      :timer.sleep(20)
      assert_receive {:next_frame, _state}

      assert {:ok, component_1} = Ecspanse.Query.fetch_component(entity, TestComponent1)
      assert component_1.value == :foo
    end
  end

  describe "command generated events" do
    test "component_created event on component creation" do
      entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})
      :timer.sleep(20)
      assert_receive {:next_frame, _state}

      assert_received {:component_created, created_component}

      {:ok, component} = Ecspanse.Query.fetch_component(entity, TestComponent1)

      assert created_component == component
    end

    test "component_deleted event on component deletion" do
      entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      {:ok, component} = Ecspanse.Query.fetch_component(entity, TestComponent1)

      Ecspanse.Command.remove_component!(component)
      :timer.sleep(20)
      assert_receive {:next_frame, _state}

      assert_received {:component_deleted, deleted_component}

      assert deleted_component == component
    end

    test "component_updated event on component update" do
      entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})
      {:ok, component} = Ecspanse.Query.fetch_component(entity, TestComponent1)
      Ecspanse.Command.update_component!(component, value: :bar)
      :timer.sleep(20)
      assert_receive {:next_frame, _state}

      assert_received {:component_updated, updated_component}
      {:ok, component} = Ecspanse.Query.fetch_component(entity, TestComponent1)

      assert updated_component == component
    end

    test "resource_created event on resource creation" do
      resource = Ecspanse.Command.insert_resource!(TestResource1)
      :timer.sleep(20)
      assert_receive {:next_frame, _state}

      assert_received {:resource_created, created_resource}

      assert created_resource == resource
    end

    test "resource_deleted event on resource deletion" do
      resource = Ecspanse.Command.insert_resource!(TestResource1)
      resource = Ecspanse.Command.delete_resource!(resource)
      :timer.sleep(20)
      assert_receive {:next_frame, _state}

      assert_received {:resource_deleted, deleted_resource}

      assert deleted_resource == resource
    end

    test "resource_updated event on resource update" do
      resource = Ecspanse.Command.insert_resource!(TestResource1)
      resource = Ecspanse.Command.update_resource!(resource, value: :bar)
      :timer.sleep(20)
      assert_receive {:next_frame, _state}

      assert_received {:resource_updated, updated_resource}

      assert updated_resource == resource
    end
  end
end
