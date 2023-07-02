defmodule Ecspanse.CommandTest do
  alias Ecspanse.WorldTest.TestResource1
  use ExUnit.Case

  defmodule TestWorld1 do
    @moduledoc false
    use Ecspanse.World

    def setup(world) do
      world
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
    assert {:ok, token} = Ecspanse.new(TestWorld1)
    # simulate commands are run from a System
    Ecspanse.System.debug(token)

    {:ok, token: token}
  end

  describe "spawn_entities!/1" do
    test "spawns multiple entities", %{token: token} do
      assert [%Ecspanse.Entity{} = entity_1, %Ecspanse.Entity{} = entity_2] =
               Ecspanse.Command.spawn_entities!([
                 {Ecspanse.Entity, components: [TestComponent1]},
                 {Ecspanse.Entity, components: [TestComponent1]}
               ])

      assert {:ok, ^entity_1} = Ecspanse.Query.fetch_entity(entity_1.id, token)
      assert {:ok, ^entity_2} = Ecspanse.Query.fetch_entity(entity_2.id, token)
    end
  end

  describe "despawn_entities!/1" do
    test "despawns multiple entities", %{token: token} do
      assert [%Ecspanse.Entity{} = entity_1, %Ecspanse.Entity{} = entity_2] =
               Ecspanse.Command.spawn_entities!([
                 {Ecspanse.Entity, components: [TestComponent1]},
                 {Ecspanse.Entity, components: [TestComponent1]}
               ])

      assert %Ecspanse.Entity{} =
               entity_3 =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [entity_1]})

      assert {:ok, ^entity_1} = Ecspanse.Query.fetch_entity(entity_1.id, token)
      assert {:ok, ^entity_2} = Ecspanse.Query.fetch_entity(entity_2.id, token)

      Ecspanse.Command.despawn_entities!([entity_1, entity_2])

      assert {:error, :not_found} = Ecspanse.Query.fetch_entity(entity_1.id, token)
      assert {:error, :not_found} = Ecspanse.Query.fetch_entity(entity_2.id, token)

      assert {:ok, ^entity_3} = Ecspanse.Query.fetch_entity(entity_3.id, token)
    end
  end

  describe "despawn_entities_and_children!/1" do
    test "despawns entities and their children", %{token: token} do
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

      Ecspanse.Command.despawn_entities_and_children!([entity_4, entity_5])

      assert {:error, :not_found} = Ecspanse.Query.fetch_entity(entity_1.id, token)
      assert {:error, :not_found} = Ecspanse.Query.fetch_entity(entity_2.id, token)
      assert {:error, :not_found} = Ecspanse.Query.fetch_entity(entity_3.id, token)
      assert {:error, :not_found} = Ecspanse.Query.fetch_entity(entity_4.id, token)
      assert {:error, :not_found} = Ecspanse.Query.fetch_entity(entity_5.id, token)
      assert {:ok, ^entity_6} = Ecspanse.Query.fetch_entity(entity_6.id, token)

      assert Ecspanse.Query.list_children(entity_6, token) == []
    end
  end

  describe "add_components!/1" do
    test "adds components to an existing entity", %{token: token} do
      assert %Ecspanse.Entity{} =
               entity =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      Ecspanse.Command.add_components!([{entity, [TestComponent2, TestComponent3]}])

      assert {:ok, {%TestComponent1{}, %TestComponent2{}, %TestComponent3{}}} =
               Ecspanse.Query.fetch_components(
                 entity,
                 {TestComponent1, TestComponent2, TestComponent3},
                 token
               )
    end
  end

  describe "update_components!/1" do
    test "updates components state", %{token: token} do
      assert %Ecspanse.Entity{} =
               entity =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert {:ok, %TestComponent1{value: :foo} = comp} =
               Ecspanse.Query.fetch_component(entity, TestComponent1, token)

      Ecspanse.Command.update_components!([{comp, value: :bar}])

      assert {:ok, %TestComponent1{value: :bar}} =
               Ecspanse.Query.fetch_component(entity, TestComponent1, token)
    end
  end

  describe "remove_components!/1" do
    test "removes components from an existing entity", %{token: token} do
      assert %Ecspanse.Entity{} =
               entity =
               Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert {:ok, %TestComponent1{} = comp} =
               Ecspanse.Query.fetch_component(entity, TestComponent1, token)

      Ecspanse.Command.remove_components!([comp])

      assert {:error, :not_found} =
               Ecspanse.Query.fetch_component(entity, TestComponent1, token)
    end
  end

  describe "add_children!/1" do
    test "adds children to an existing entity", %{token: token} do
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

      assert [^child_1, ^child_2] = Ecspanse.Query.list_children(entity, token)
    end
  end

  describe "add_parents!/1" do
    test "adds parents to an existing entity", %{token: token} do
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

      assert [^parent_1, ^parent_2] = Ecspanse.Query.list_parents(entity, token)
    end
  end

  describe "remove_children!/1" do
    test "removes children from an existing entity", %{token: token} do
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

      assert [^child_1, ^child_2] = Ecspanse.Query.list_children(entity, token)

      Ecspanse.Command.remove_children!([{entity, [child_1]}])

      assert [^child_2] = Ecspanse.Query.list_children(entity, token)
    end
  end

  describe "remove_parents!/1" do
    test "removes parents from an existing entity", %{token: token} do
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

      assert [^parent_1, ^parent_2] = Ecspanse.Query.list_parents(entity, token)

      Ecspanse.Command.remove_parents!([{entity, [parent_1]}])

      assert [^parent_2] = Ecspanse.Query.list_parents(entity, token)
    end
  end

  describe "insert_resource!/1" do
    test "inserts a resource in the world", %{token: token} do
      assert {:error, :not_found} =
               Ecspanse.Query.fetch_resource(TestResource1, token)

      assert %TestResource1{} = Ecspanse.Command.insert_resource!({TestResource1, value: :bar})

      assert {:ok, %TestResource1{value: :bar}} =
               Ecspanse.Query.fetch_resource(TestResource1, token)
    end
  end

  describe "update_resource!/2" do
    test "updates a resource state", %{token: token} do
      assert %TestResource1{} =
               resource = Ecspanse.Command.insert_resource!({TestResource1, value: :bar})

      Ecspanse.Command.update_resource!(resource, value: :foo)

      assert {:ok, %TestResource1{value: :foo}} =
               Ecspanse.Query.fetch_resource(TestResource1, token)
    end
  end

  describe "delete_resource!/1" do
    test "deletes a resource from the world", %{token: token} do
      assert %TestResource1{} =
               resource = Ecspanse.Command.insert_resource!({TestResource1, value: :bar})

      assert {:ok, %TestResource1{value: :bar}} =
               Ecspanse.Query.fetch_resource(TestResource1, token)

      Ecspanse.Command.delete_resource!(resource)

      assert {:error, :not_found} =
               Ecspanse.Query.fetch_resource(TestResource1, token)
    end
  end
end
