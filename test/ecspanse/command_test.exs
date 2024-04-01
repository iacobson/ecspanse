defmodule Ecspanse.CommandTest do
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
    use Ecspanse.Component, state: [value: :foo]
  end

  defmodule TestComponent2 do
    @moduledoc false
    use Ecspanse.Component
  end

  defmodule TestComponent3 do
    @moduledoc false
    use Ecspanse.Component
  end

  defmodule TestResource1 do
    @moduledoc false
    use Ecspanse.Resource, state: [value: :foo]
  end

  setup do
    start_supervised({TestServer1, :test})
    Ecspanse.Server.test_server(self())
    # simulate commands are run from a System
    Ecspanse.System.debug()

    :ok
  end

  describe "spawn_entities!/1" do
    test "spawns multiple entities" do
      assert [%Ecspanse.Entity{} = entity_1, %Ecspanse.Entity{} = entity_2] =
               Ecspanse.Command.spawn_entities!([
                 {Ecspanse.Entity, components: [{TestComponent1, [value: :bar], [:tag1, :tag2]}]},
                 {Ecspanse.Entity, components: [TestComponent1]}
               ])

      assert {:ok, ^entity_1} = Ecspanse.Query.fetch_entity(entity_1.id)
      assert {:ok, ^entity_2} = Ecspanse.Query.fetch_entity(entity_2.id)
    end
  end

  describe "despawn_entities!/1" do
    test "despawns multiple entities" do
      assert [%Ecspanse.Entity{} = entity_1, %Ecspanse.Entity{} = entity_2] =
               Ecspanse.Command.spawn_entities!([
                 {Ecspanse.Entity, components: [TestComponent1]},
                 {Ecspanse.Entity, components: [TestComponent1]}
               ])

      assert %Ecspanse.Entity{} =
               entity_3 =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [entity_1]})

      assert {:ok, ^entity_1} = Ecspanse.Query.fetch_entity(entity_1.id)
      assert {:ok, ^entity_2} = Ecspanse.Query.fetch_entity(entity_2.id)

      Ecspanse.Command.despawn_entities!([entity_1, entity_2])

      assert {:error, :not_found} = Ecspanse.Query.fetch_entity(entity_1.id)
      assert {:error, :not_found} = Ecspanse.Query.fetch_entity(entity_2.id)

      assert {:ok, ^entity_3} = Ecspanse.Query.fetch_entity(entity_3.id)
    end
  end

  describe "despawn_entities_and_descendants!/1" do
    test "despawns entities and their children" do
      assert %Ecspanse.Entity{} =
               entity_1 =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [entity_1]})
      entity_3 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [entity_2]})

      assert [
               %Ecspanse.Entity{} = entity_4,
               %Ecspanse.Entity{} = entity_5,
               %Ecspanse.Entity{} = entity_6
             ] =
               Ecspanse.Command.spawn_entities!([
                 {Ecspanse.Entity, children: [entity_1, entity_3]},
                 {Ecspanse.Entity, children: [entity_2]},
                 {Ecspanse.Entity, children: [entity_1, entity_2, entity_3]}
               ])

      Ecspanse.Command.despawn_entities_and_descendants!([entity_4, entity_5])

      assert {:error, :not_found} = Ecspanse.Query.fetch_entity(entity_1.id)
      assert {:error, :not_found} = Ecspanse.Query.fetch_entity(entity_2.id)
      assert {:error, :not_found} = Ecspanse.Query.fetch_entity(entity_3.id)
      assert {:error, :not_found} = Ecspanse.Query.fetch_entity(entity_4.id)
      assert {:error, :not_found} = Ecspanse.Query.fetch_entity(entity_5.id)
      assert {:ok, ^entity_6} = Ecspanse.Query.fetch_entity(entity_6.id)

      assert Ecspanse.Query.list_children(entity_6) == []
    end
  end

  describe "clone_entity!/2" do
    test "create a clone of the entity" do
      entity =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [
             {TestComponent1, [value: :bar], [:tag_1, :tag_2]},
             TestComponent2,
             TestComponent3
           ]}
        )

      parent_entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, children: [entity]})

      clone = Ecspanse.Command.clone_entity!(entity)

      entity_components = Ecspanse.Query.list_components(entity)
      clone_components = Ecspanse.Query.list_components(clone)

      assert [parent_entity] == Ecspanse.Query.list_parents(entity)
      # relationships are not cloned
      assert [] = Ecspanse.Query.list_parents(clone)

      entity_component_modules = entity_components |> Enum.map(& &1.__struct__)
      cloned_entity_component_modules = clone_components |> Enum.map(& &1.__struct__)

      assert [] == entity_component_modules -- cloned_entity_component_modules

      {:ok, entity_component_1} = TestComponent1.fetch(entity)
      {:ok, cloned_entity_component_1} = TestComponent1.fetch(clone)

      assert entity_component_1.value == cloned_entity_component_1.value

      assert Ecspanse.Query.list_tags(entity_component_1) ==
               Ecspanse.Query.list_tags(cloned_entity_component_1)
    end

    test "create a named clone of an entity" do
      entity =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, id: "alpha", components: [TestComponent1]}
        )

      assert entity.id == "alpha"

      clone = Ecspanse.Command.clone_entity!(entity, id: "beta")

      assert clone.id == "beta"
    end
  end

  describe "deep_clone_entity/2" do
    test "create a clone of the entity and all its descendants" do
      assert %Ecspanse.Entity{} =
               root_entity =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      entity_1 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [root_entity]})
      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [entity_1]})
      _entity_3 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [entity_2]})
      _entity_4 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [root_entity]})

      cloned_entity = Ecspanse.Command.deep_clone_entity!(root_entity)

      root_entity_children = Ecspanse.Query.list_children(root_entity)
      cloned_entity_children = Ecspanse.Query.list_children(cloned_entity)

      assert length(root_entity_children) == length(cloned_entity_children)

      root_entity_descendants = Ecspanse.Query.list_descendants(root_entity)
      cloned_entity_descendants = Ecspanse.Query.list_descendants(cloned_entity)

      assert length(root_entity_descendants) == length(cloned_entity_descendants)
    end

    test "create a named deep clone of an entity" do
      assert %Ecspanse.Entity{} =
               root_entity =
               Ecspanse.Command.spawn_entity!(
                 {Ecspanse.Entity, id: "alpha", components: [TestComponent1]}
               )

      entity_1 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [root_entity]})
      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [entity_1]})
      _entity_3 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [entity_2]})
      _entity_4 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [root_entity]})

      assert root_entity.id == "alpha"

      cloned_entity = Ecspanse.Command.deep_clone_entity!(root_entity, id: "beta")

      assert cloned_entity.id == "beta"
    end
  end

  describe "add_components!/1" do
    test "adds components to an existing entity" do
      assert %Ecspanse.Entity{} =
               entity =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      Ecspanse.Command.add_components!([
        {entity, [{TestComponent2, [], [:tag1, :tag_2]}, TestComponent3]}
      ])

      assert {:ok, {%TestComponent1{}, %TestComponent2{}, %TestComponent3{}}} =
               Ecspanse.Query.fetch_components(
                 entity,
                 {TestComponent1, TestComponent2, TestComponent3}
               )
    end
  end

  describe "add_and_fetch_component!/2" do
    test "adds a component to an existing entity and fetches it" do
      assert %Ecspanse.Entity{} =
               entity =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert {:ok, %TestComponent2{}} =
               Ecspanse.Command.add_and_fetch_component!(entity, TestComponent2)

      assert {:ok, %TestComponent2{}} = TestComponent2.fetch(entity)
    end
  end

  describe "update_components!/1" do
    test "updates components state" do
      assert %Ecspanse.Entity{} =
               entity =
               Ecspanse.Command.spawn_entity!(
                 {Ecspanse.Entity, components: [{TestComponent1, [], [:tag1]}]}
               )

      assert {:ok, %TestComponent1{value: :foo} = comp} =
               Ecspanse.Query.fetch_component(entity, TestComponent1)

      Ecspanse.Command.update_components!([{comp, value: :bar}])

      assert {:ok, %TestComponent1{value: :bar}} =
               Ecspanse.Query.fetch_component(entity, TestComponent1)
    end
  end

  describe "update_and_fetch_component!/2" do
    test "updates a component state and fetches it" do
      assert %Ecspanse.Entity{} =
               entity =
               Ecspanse.Command.spawn_entity!(
                 {Ecspanse.Entity, components: [{TestComponent1, [], [:tag1]}]}
               )

      assert {:ok, %TestComponent1{value: :foo} = comp} = TestComponent1.fetch(entity)

      assert {:ok, %TestComponent1{value: :bar}} =
               Ecspanse.Command.update_and_fetch_component!(comp, value: :bar)

      assert {:ok, %TestComponent1{value: :bar}} = TestComponent1.fetch(entity)
    end
  end

  describe "remove_components!/1" do
    test "removes components from an existing entity" do
      assert %Ecspanse.Entity{} =
               entity =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert {:ok, %TestComponent1{} = comp} =
               Ecspanse.Query.fetch_component(entity, TestComponent1)

      Ecspanse.Command.remove_components!([comp])

      assert {:error, :not_found} =
               Ecspanse.Query.fetch_component(entity, TestComponent1)
    end
  end

  describe "add_children!/1" do
    test "adds children to an existing entity" do
      assert %Ecspanse.Entity{} =
               entity =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert %Ecspanse.Entity{} =
               child_1 =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert %Ecspanse.Entity{} =
               child_2 =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      Ecspanse.Command.add_children!([{entity, [child_1, child_2]}])

      assert [^child_1, ^child_2] = Ecspanse.Query.list_children(entity)
    end
  end

  describe "add_parents!/1" do
    test "adds parents to an existing entity" do
      assert %Ecspanse.Entity{} =
               entity =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert %Ecspanse.Entity{} =
               parent_1 =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert %Ecspanse.Entity{} =
               parent_2 =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      Ecspanse.Command.add_parents!([{entity, [parent_1, parent_2]}])

      assert [^parent_1, ^parent_2] = Ecspanse.Query.list_parents(entity)
    end
  end

  describe "remove_children!/1" do
    test "removes children from an existing entity" do
      assert %Ecspanse.Entity{} =
               entity =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert %Ecspanse.Entity{} =
               child_1 =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert %Ecspanse.Entity{} =
               child_2 =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      Ecspanse.Command.add_children!([{entity, [child_1, child_2]}])

      assert [^child_1, ^child_2] = Ecspanse.Query.list_children(entity)

      Ecspanse.Command.remove_children!([{entity, [child_1]}])

      assert [^child_2] = Ecspanse.Query.list_children(entity)
    end
  end

  describe "remove_parents!/1" do
    test "removes parents from an existing entity" do
      assert %Ecspanse.Entity{} =
               entity =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert %Ecspanse.Entity{} =
               parent_1 =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert %Ecspanse.Entity{} =
               parent_2 =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      Ecspanse.Command.add_parents!([{entity, [parent_1, parent_2]}])

      assert [^parent_1, ^parent_2] = Ecspanse.Query.list_parents(entity)

      Ecspanse.Command.remove_parents!([{entity, [parent_1]}])

      assert [^parent_2] = Ecspanse.Query.list_parents(entity)
    end
  end

  describe "insert_resource!/1" do
    test "inserts a resource" do
      assert {:error, :not_found} =
               Ecspanse.Query.fetch_resource(TestResource1)

      assert %TestResource1{} = Ecspanse.Command.insert_resource!({TestResource1, value: :bar})

      assert {:ok, %TestResource1{value: :bar}} =
               Ecspanse.Query.fetch_resource(TestResource1)
    end
  end

  describe "update_resource!/2" do
    test "updates a resource state" do
      assert %TestResource1{} =
               resource = Ecspanse.Command.insert_resource!({TestResource1, value: :bar})

      Ecspanse.Command.update_resource!(resource, value: :foo)

      assert {:ok, %TestResource1{value: :foo}} =
               Ecspanse.Query.fetch_resource(TestResource1)
    end
  end

  describe "delete_resource!/1" do
    test "deletes a resource" do
      assert %TestResource1{} =
               resource = Ecspanse.Command.insert_resource!({TestResource1, value: :bar})

      assert {:ok, %TestResource1{value: :bar}} =
               Ecspanse.Query.fetch_resource(TestResource1)

      Ecspanse.Command.delete_resource!(resource)

      assert {:error, :not_found} =
               Ecspanse.Query.fetch_resource(TestResource1)
    end
  end
end
