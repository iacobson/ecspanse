defmodule Ecspanse.SnapshotTest do
  use ExUnit.Case

  defmodule TestServer1 do
    @moduledoc false
    use Ecspanse

    def setup(data) do
      data
    end
  end

  defmodule TestComponent1 do
    @moduledoc false
    use Ecspanse.Component, state: [value: :foo], tags: [:alpha]
  end

  defmodule TestComponent2 do
    @moduledoc false
    use Ecspanse.Component
  end

  defmodule TestComponent3 do
    @moduledoc false
    use Ecspanse.Component, export_filter: :component
  end

  defmodule TestComponent4 do
    @moduledoc false
    use Ecspanse.Component, export_filter: :entity
  end

  defmodule TestResource1 do
    @moduledoc false
    use Ecspanse.Resource, state: [value: :foo]
  end

  defmodule TestResource2 do
    @moduledoc false
    use Ecspanse.Resource, state: [value: :foo], export_filter: :resource
  end

  setup do
    start_supervised({TestServer1, :test})
    Ecspanse.Server.test_server(self())
    # simulate commands are run from a System
    Ecspanse.System.debug()

    :ok
  end

  describe "export_entities!/0" do
    test "export entities with components without export filters" do
      [entity1, entity2, entity3] =
        Ecspanse.Command.spawn_entities!([
          {Ecspanse.Entity, components: [TestComponent1]},
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]},
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3, TestComponent4]}
        ])

      snapshots = Ecspanse.Snapshot.export_entities!()

      assert snapshot1 = Enum.find(snapshots, &(&1.entity_id == entity1.id))
      assert TestComponent1 in snapshot1.component_modules

      assert snapshot2 = Enum.find(snapshots, &(&1.entity_id == entity2.id))
      assert TestComponent1 in snapshot2.component_modules
      assert TestComponent2 in snapshot2.component_modules
      # TestComponent3 has a filter that excludes it from the snapshot
      refute TestComponent3 in snapshot2.component_modules

      # TestComponent4 is filtering out the entity
      refute Enum.find(snapshots, &(&1.entity_id == entity3.id))
    end
  end

  describe "export_entity!/1" do
    test "export entity with components without export filters" do
      entity =
        Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]})

      snapshot = Ecspanse.Snapshot.export_entity!(entity)

      assert snapshot
      assert snapshot.entity_id == entity.id
      assert TestComponent1 in snapshot.component_modules
      assert TestComponent2 in snapshot.component_modules
      refute TestComponent3 in snapshot.component_modules
    end

    test "does not export an entity with components with entity export filter" do
      entity =
        Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent4]})

      snapshot = Ecspanse.Snapshot.export_entity!(entity)

      refute snapshot
    end
  end

  describe "export_entity_with_descendants!/1" do
    test "export an entity and its descendants" do
      entity1 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})
      entity2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1], parents: [entity1]})
      entity3 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1], parents: [entity2]})
      entity4 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      snapshots = Ecspanse.Snapshot.export_entity_with_descendants!(entity1)

      assert Enum.find(snapshots, &(&1.entity_id == entity1.id))
      assert Enum.find(snapshots, &(&1.entity_id == entity2.id))
      assert Enum.find(snapshots, &(&1.entity_id == entity3.id))
      refute Enum.find(snapshots, &(&1.entity_id == entity4.id))
    end
  end

  describe "export_custom_entities!/1" do
    test "export a list of custom entities" do
      entity1 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})
      entity2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})
      entity3 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      snapshots = Ecspanse.Snapshot.export_custom_entities!([entity1, entity3])

      assert Enum.find(snapshots, &(&1.entity_id == entity1.id))
      refute Enum.find(snapshots, &(&1.entity_id == entity2.id))
      assert Enum.find(snapshots, &(&1.entity_id == entity3.id))
    end
  end

  describe "export_resources!/0" do
    test "export resources without export filters" do
      Ecspanse.Command.insert_resource!(TestResource1)
      Ecspanse.Command.insert_resource!(TestResource2)

      snapshots = Ecspanse.Snapshot.export_resources!()

      assert Enum.find(snapshots, &(&1.resource_module == TestResource1))

      # TestResource2 has a filter that excludes it from the snapshot
      refute Enum.find(snapshots, &(&1.resource_module == TestResource2))
    end
  end

  describe "restore_entities_from_snapshots!/1" do
    test "creates entities from a list of entity snapshots" do
      entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [{TestComponent1, [], [:beta]}]})
      {:ok, component} = TestComponent1.fetch(entity)
      Ecspanse.Command.update_component!(component, value: :bar)

      snapshots = Ecspanse.Snapshot.export_entities!()

      Ecspanse.Command.despawn_entity_and_descendants!(entity)

      assert {:error, :not_found} = TestComponent1.fetch(entity)

      Ecspanse.Snapshot.restore_entities_from_snapshots!(snapshots)

      assert {:ok, restored_component} = TestComponent1.fetch(entity)
      assert restored_component.value == :bar
      assert restored_component.__meta__.tags == MapSet.new([:alpha, :beta])
    end

    test "overwrites existing entities components" do
      entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})
      {:ok, component} = TestComponent1.fetch(entity)

      snapshots = Ecspanse.Snapshot.export_entities!()

      {:ok, component} = Ecspanse.Command.update_and_fetch_component!(component, value: :bar)

      assert component.value == :bar

      Ecspanse.Snapshot.restore_entities_from_snapshots!(snapshots)

      assert {:ok, restored_component} = TestComponent1.fetch(entity)
      assert restored_component.value == :foo
    end

    test "preserves exported and restored entities relationships" do
      entity1 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})
      entity2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1], parents: [entity1]})
      entity3 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1], parents: [entity2]})

      snapshots = Ecspanse.Snapshot.export_entities!()

      Ecspanse.Command.despawn_entity_and_descendants!(entity1)

      assert {:error, :not_found} = Ecspanse.Entity.fetch(entity1.id)
      assert {:error, :not_found} = Ecspanse.Entity.fetch(entity2.id)
      assert {:error, :not_found} = Ecspanse.Entity.fetch(entity3.id)

      Ecspanse.Snapshot.restore_entities_from_snapshots!(snapshots)

      assert {:ok, restored_entity1} = Ecspanse.Entity.fetch(entity1.id)

      assert {:ok, restored_entity2} = Ecspanse.Entity.fetch(entity2.id)

      assert {:ok, restored_entity3} = Ecspanse.Entity.fetch(entity3.id)

      assert Ecspanse.Query.is_parent_of?(parent: restored_entity1, child: restored_entity2)
      assert Ecspanse.Query.is_parent_of?(parent: restored_entity2, child: restored_entity3)
    end
  end

  describe "restore_resources_from_snapshots!/1" do
    test "creates resources from a list of resource snapshots" do
      resource = Ecspanse.Command.insert_resource!(TestResource1)

      snapshots = Ecspanse.Snapshot.export_resources!()

      Ecspanse.Command.delete_resource!(resource)

      assert {:error, :not_found} = TestResource1.fetch()

      Ecspanse.Snapshot.restore_resources_from_snapshots!(snapshots)

      assert {:ok, restored_resource} = TestResource1.fetch()
      assert restored_resource.value == :foo
    end

    test "overwrites existing resources" do
      Ecspanse.Command.insert_resource!(TestResource1)
      {:ok, resource} = TestResource1.fetch()

      snapshots = Ecspanse.Snapshot.export_resources!()

      resource = Ecspanse.Command.update_resource!(resource, value: :bar)

      assert resource.value == :bar

      Ecspanse.Snapshot.restore_resources_from_snapshots!(snapshots)

      assert {:ok, restored_resource} = TestResource1.fetch()
      assert restored_resource.value == :foo
    end
  end

  describe "restore_entity/2 and restore_entities/1" do
    test "restore entity from a list of component specs" do
      entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})
      assert {:ok, component1} = TestComponent1.fetch(entity)
      assert component1.value == :foo
      assert component1.__meta__.tags == MapSet.new([:alpha])

      assert {:error, :not_found} = TestComponent2.fetch(entity)

      Ecspanse.Snapshot.restore_entity!(entity.id, [
        {TestComponent1, [value: :bar], [:beta]},
        TestComponent2
      ])

      assert {:ok, restored_component1} = TestComponent1.fetch(entity)
      assert restored_component1.value == :bar
      assert restored_component1.__meta__.tags == MapSet.new([:alpha, :beta])

      assert {:ok, _restored_component2} = TestComponent2.fetch(entity)
    end
  end

  describe "restore_resource/2 and restore_resources/1" do
    test "restore resource from a resource spec" do
      resource1 = Ecspanse.Command.insert_resource!(TestResource1)
      assert resource1.value == :foo

      assert {:error, :not_found} = TestResource2.fetch()

      Ecspanse.Snapshot.restore_resources!([{TestResource1, [value: :bar]}, TestResource2])

      assert {:ok, restored_resource1} = TestResource1.fetch()
      assert restored_resource1.value == :bar

      assert {:ok, _restored_resource2} = TestResource2.fetch()
    end
  end

  describe "show_invalid_relationships/0 and remove_invalid_relationships!/0" do
    test "show and remove invalid relationships" do
      entity1 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})
      entity2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1], parents: [entity1]})
      entity3 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1], children: [entity1]})

      snapshot = Ecspanse.Snapshot.export_entity!(entity1)

      Ecspanse.Command.despawn_entity_and_descendants!(entity3)

      assert {:error, :not_found} = Ecspanse.Entity.fetch(entity1.id)
      assert {:error, :not_found} = Ecspanse.Entity.fetch(entity2.id)
      assert {:error, :not_found} = Ecspanse.Entity.fetch(entity3.id)

      Ecspanse.Snapshot.restore_entities_from_snapshots!([snapshot])

      assert {:ok, restored_entity1} = Ecspanse.Entity.fetch(entity1.id)

      %{
        invalid_parent_relationships: [{^restored_entity1, [invalid_parent]}],
        invalid_child_relationships: [{^restored_entity1, [invalid_child]}]
      } =
        Ecspanse.Snapshot.show_invalid_relationships()

      assert invalid_parent.id == entity3.id
      assert invalid_child.id == entity2.id

      Ecspanse.Snapshot.remove_invalid_relationships!()

      %{
        invalid_parent_relationships: [],
        invalid_child_relationships: []
      } =
        Ecspanse.Snapshot.show_invalid_relationships()
    end
  end
end
