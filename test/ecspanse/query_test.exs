defmodule Ecspanse.QueryTest do
  use ExUnit.Case

  defmodule TestComponent1 do
    @moduledoc false
    use Ecspanse.Component
  end

  defmodule TestComponent2 do
    @moduledoc false
    use Ecspanse.Component
  end

  defmodule TestComponent3 do
    @moduledoc false
    use Ecspanse.Component
  end

  defmodule TestComponent4 do
    @moduledoc false
    use Ecspanse.Component, groups: [:foo, :bar]
  end

  defmodule TestComponent5 do
    @moduledoc false
    use Ecspanse.Component, groups: [:foo, :baz], access_mode: :entity_type
  end

  defmodule TestResource1 do
    @moduledoc false
    use Ecspanse.Resource
  end

  defmodule TestServer1 do
    @moduledoc false
    use Ecspanse

    def setup(data) do
      data
    end
  end

  ###

  setup do
    start_supervised(TestServer1)
    Ecspanse.Server.test_server(self())
    # simulate commands are run from a System
    Ecspanse.System.debug()

    :ok
  end

  describe "select/2" do
    test "returns components for entities with all components" do
      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
      )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
      )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent2]}
      )

      assert components =
               Ecspanse.Query.select({TestComponent1, TestComponent2, TestComponent3})
               |> Ecspanse.Query.stream()
               |> Enum.to_list()

      assert length(components) == 2

      assert [
               {%TestComponent1{}, %TestComponent2{}, %TestComponent3{}},
               {%TestComponent1{}, %TestComponent2{}, %TestComponent3{}}
             ] = components
    end

    test "returns also the entities if they are the first element of the query tuple" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
        )

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
        )

      _entity_3 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2]}
        )

      assert components =
               Ecspanse.Query.select(
                 {Ecspanse.Entity, TestComponent1, TestComponent2, TestComponent3}
               )
               |> Ecspanse.Query.stream()
               |> Enum.to_list()

      assert length(components) == 2

      for {entity, _, _, _} <- components do
        assert entity.id in [entity_1.id, entity_2.id]
      end
    end

    test "can query entities relations" do
      entity_1 =
        Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      entity_2 =
        Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      entity_3 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, parents: [entity_1], children: [entity_2]}
        )

      assert {children_comp, parents_comp} =
               Ecspanse.Query.select(
                 {Ecspanse.Component.Children, Ecspanse.Component.Parents},
                 for: [entity_3]
               )
               |> Ecspanse.Query.one()

      assert children_comp.entities == [entity_2]
      assert parents_comp.entities == [entity_1]
    end

    test "can query optional components" do
      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
      )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
      )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent2]}
      )

      assert components =
               Ecspanse.Query.select({TestComponent1, TestComponent2, opt: TestComponent3})
               |> Ecspanse.Query.stream()
               |> Enum.to_list()

      assert length(components) == 3
    end

    test "can filter for existing components that are not in the query tuple" do
      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
      )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent2, TestComponent3]}
      )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent2]}
      )

      assert components =
               Ecspanse.Query.select({TestComponent1}, with: [TestComponent3])
               |> Ecspanse.Query.stream()
               |> Enum.to_list()

      assert length(components) == 1
    end

    test "can filter out components that are not in the query tuple" do
      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent2]}
      )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
      )

      Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert components =
               Ecspanse.Query.select({TestComponent1},
                 with: [TestComponent2, without: [TestComponent3]]
               )
               |> Ecspanse.Query.stream()
               |> Enum.to_list()

      assert length(components) == 1
    end

    test "can apply multiple filters" do
      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent2]}
      )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
      )

      Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert components =
               Ecspanse.Query.select({TestComponent1},
                 with: [TestComponent2, without: [TestComponent3]],
                 or_with: [TestComponent3]
               )
               |> Ecspanse.Query.stream()
               |> Enum.to_list()

      assert length(components) == 2
    end

    test "can filter results for specific entities" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
        )

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
        )

      _entity_3 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
        )

      assert components =
               Ecspanse.Query.select({TestComponent1, TestComponent2, TestComponent3},
                 for: [entity_1, entity_2]
               )
               |> Ecspanse.Query.stream()
               |> Enum.to_list()

      assert length(components) == 2
    end

    test "can filter out results for specific entities" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
        )

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
        )

      _entity_3 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
        )

      assert components =
               Ecspanse.Query.select({TestComponent1, TestComponent2, TestComponent3},
                 not_for: [entity_1, entity_2]
               )
               |> Ecspanse.Query.stream()
               |> Enum.to_list()

      assert length(components) == 1
    end

    test "can query just children of entities" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
        )

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2]}
        )

      entity_3 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [TestComponent1, TestComponent2, TestComponent3],
           children: [entity_1, entity_2]}
        )

      assert components =
               Ecspanse.Query.select({TestComponent1, TestComponent2, TestComponent3},
                 for_children_of: [entity_3]
               )
               |> Ecspanse.Query.stream()
               |> Enum.to_list()

      assert length(components) == 1
    end

    test "can query just parents of entities" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
        )

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [TestComponent1, TestComponent2, TestComponent3], parents: [entity_1]}
        )

      entity_3 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [TestComponent1, TestComponent2, TestComponent3], parents: [entity_1]}
        )

      assert components =
               Ecspanse.Query.select({TestComponent1, TestComponent2, TestComponent3},
                 for_parents_of: [entity_2, entity_3]
               )
               |> Ecspanse.Query.stream()
               |> Enum.to_list()

      assert length(components) == 1
    end

    test "can return only one result and not a stream" do
      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
      )

      assert {_, _, _} =
               Ecspanse.Query.select({TestComponent1, TestComponent2, TestComponent3})
               |> Ecspanse.Query.one()
    end
  end

  describe "fetch_entity/2" do
    test "returns the entity for a component" do
      entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert {:ok, ^entity} = Ecspanse.Query.fetch_entity(entity.id)
    end

    test "returns error if the entity does not exist" do
      assert {:error, :not_found} = Ecspanse.Query.fetch_entity(UUID.uuid4())
    end
  end

  describe "get_component_entity/2" do
    test "returns the entity for a component" do
      entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert {component} =
               Ecspanse.Query.select({TestComponent1}, for: [entity])
               |> Ecspanse.Query.one()

      assert entity == Ecspanse.Query.get_component_entity(component)
    end
  end

  describe "list_children/2" do
    test "returns the children of an entity" do
      entity_1 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, [components: [TestComponent1]]})

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, [components: [TestComponent1]]})

      entity_3 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, children: [entity_1, entity_2]})

      assert [entity_1, entity_2] == Ecspanse.Query.list_children(entity_3)
    end
  end

  describe "list_parents/2" do
    test "returns the parents of an entity" do
      entity_1 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, [components: [TestComponent1]]})

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [entity_1]})

      entity_3 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, children: [entity_2]})

      assert [entity_1, entity_3] == Ecspanse.Query.list_parents(entity_2)
    end
  end

  describe "list_group_components/2" do
    test "returns the components of a group" do
      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity,
         components: [TestComponent1, TestComponent2, TestComponent4, TestComponent5]}
      )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent4]}
      )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent3, TestComponent5]}
      )

      components = Ecspanse.Query.list_group_components(:foo)

      assert length(components) == 4

      for %comp_module{} <- components do
        assert comp_module in [TestComponent4, TestComponent5]
      end
    end
  end

  describe "list_group_components/3" do
    test "returns the components of a group for a given entity" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [TestComponent1, TestComponent2, TestComponent4, TestComponent5]}
        )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent4]}
      )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent3, TestComponent5]}
      )

      components = Ecspanse.Query.list_group_components(entity_1, :bar)

      assert length(components) == 1

      assert [%TestComponent4{}] = components
    end
  end

  describe "fetch_component/3" do
    test "returns a component for a given entity" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [TestComponent1, TestComponent2, TestComponent4, TestComponent5]}
        )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent4]}
      )

      assert {:ok, %TestComponent1{} = component} =
               Ecspanse.Query.fetch_component(entity_1, TestComponent1)

      entity = Ecspanse.Query.get_component_entity(component)
      assert entity == entity_1
    end
  end

  describe "fetch_components/3" do
    test "returns a tuple of components if the entity has all of them" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [TestComponent1, TestComponent2, TestComponent4, TestComponent5]}
        )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent4]}
      )

      assert {:ok, {%TestComponent1{} = component_1, %TestComponent4{} = component_2}} =
               Ecspanse.Query.fetch_components(entity_1, {TestComponent1, TestComponent4})

      entity = Ecspanse.Query.get_component_entity(component_1)
      assert entity == entity_1

      entity = Ecspanse.Query.get_component_entity(component_2)
      assert entity == entity_1
    end
  end

  describe "is_type?/3" do
    test "checks if an entity has a certain entity_type component" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5]}
        )

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert Ecspanse.Query.is_type?(entity_1, TestComponent5)
      refute Ecspanse.Query.is_type?(entity_2, TestComponent5)
    end
  end

  describe "has_component?/3" do
    test "checks if an entity has a certain component" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5]}
        )

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert Ecspanse.Query.has_component?(entity_1, TestComponent5)
      refute Ecspanse.Query.has_component?(entity_2, TestComponent5)
    end
  end

  describe "has_components?/3" do
    test "check if an entity has all of the given components" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5]}
        )

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert Ecspanse.Query.has_components?(entity_1, [TestComponent1, TestComponent5])
      refute Ecspanse.Query.has_components?(entity_2, [TestComponent1, TestComponent5])
    end
  end

  describe "has_children_with_type?/3" do
    test "checks if an entity has children with a certain entity_type component" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5]}
        )

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5], children: [entity_1]}
        )

      refute Ecspanse.Query.has_children_with_type?(entity_1, TestComponent5)
      assert Ecspanse.Query.has_children_with_type?(entity_2, TestComponent5)
    end
  end

  describe "has_children_with_component?/3" do
    test "checks if an entity has children with a certain component" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5]}
        )

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1], children: [entity_1]}
        )

      refute Ecspanse.Query.has_children_with_component?(entity_1, TestComponent1)
      assert Ecspanse.Query.has_children_with_component?(entity_2, TestComponent1)
    end
  end

  describe "has_children_with_components?/3" do
    test "checks if an entity has children with all of the given components" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5]}
        )

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5], children: [entity_1]}
        )

      refute Ecspanse.Query.has_children_with_components?(
               entity_1,
               [TestComponent1, TestComponent5]
             )

      assert Ecspanse.Query.has_children_with_components?(
               entity_2,
               [TestComponent1, TestComponent5]
             )
    end
  end

  describe "has_parents_with_type?/3" do
    test "checks if an entity has parents with a certain entity_type component" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5]}
        )

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5], parents: [entity_1]}
        )

      refute Ecspanse.Query.has_parents_with_type?(entity_1, TestComponent5)
      assert Ecspanse.Query.has_parents_with_type?(entity_2, TestComponent5)
    end
  end

  describe "has_parents_with_component?/3" do
    test "checks if an entity has parents with a certain component" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5]}
        )

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1], parents: [entity_1]}
        )

      refute Ecspanse.Query.has_parents_with_component?(entity_1, TestComponent1)
      assert Ecspanse.Query.has_parents_with_component?(entity_2, TestComponent1)
    end
  end

  describe "has_parents_with_components?/3" do
    test "checks if an entity has parents with all of the given components" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5]}
        )

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5], parents: [entity_1]}
        )

      refute Ecspanse.Query.has_parents_with_components?(entity_1, [
               TestComponent1,
               TestComponent5
             ])

      assert Ecspanse.Query.has_parents_with_components?(entity_2, [
               TestComponent1,
               TestComponent5
             ])
    end
  end

  describe "fetch_resource/2" do
    test "fetches a resource from the world" do
      resource = Ecspanse.Command.insert_resource!(TestResource1)

      assert {:ok, ^resource} = Ecspanse.Query.fetch_resource(TestResource1)
    end
  end
end
