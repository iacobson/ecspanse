defmodule Ecspanse.QueryTest do
  alias Ecspanse.WorldTest.TestComponent1
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

  describe "select/2" do
    test "kreturn components for entities with all components" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

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
               |> Ecspanse.Query.stream(token)
               |> Enum.to_list()

      assert length(components) == 2

      assert [
               {%TestComponent1{}, %TestComponent2{}, %TestComponent3{}},
               {%TestComponent1{}, %TestComponent2{}, %TestComponent3{}}
             ] = components
    end

    test "returns also the entities if they are the first element of the query tuple" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

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
               |> Ecspanse.Query.stream(token)
               |> Enum.to_list()

      assert length(components) == 2

      for {entity, _, _, _} <- components do
        assert entity.id in [entity_1.id, entity_2.id]
      end
    end

    test "can query optional components" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

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
               |> Ecspanse.Query.stream(token)
               |> Enum.to_list()

      assert length(components) == 3
    end

    test "can filter for existing components that are not in the query tuple" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

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
               |> Ecspanse.Query.stream(token)
               |> Enum.to_list()

      assert length(components) == 1
    end

    test "can filter out components that are not in the query tuple" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

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
               |> Ecspanse.Query.stream(token)
               |> Enum.to_list()

      assert length(components) == 1
    end

    test "can apply multiple filters" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

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
               |> Ecspanse.Query.stream(token)
               |> Enum.to_list()

      assert length(components) == 2
    end

    test "can filter results for specific entities" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

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
               |> Ecspanse.Query.stream(token)
               |> Enum.to_list()

      assert length(components) == 2
    end

    test "can filter out results for specific entities" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

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
               |> Ecspanse.Query.stream(token)
               |> Enum.to_list()

      assert length(components) == 1
    end

    test "can query just children of entities" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

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
               |> Ecspanse.Query.stream(token)
               |> Enum.to_list()

      assert length(components) == 1
    end

    test "can query just parents of entities" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

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
               |> Ecspanse.Query.stream(token)
               |> Enum.to_list()

      assert length(components) == 1
    end

    test "can return only one result and not a stream" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent2, TestComponent3]}
      )

      assert {_, _, _} =
               Ecspanse.Query.select({TestComponent1, TestComponent2, TestComponent3})
               |> Ecspanse.Query.one(token)
    end
  end

  describe "get_component_entity/2" do
    test "returns the entity for a component" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

      entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert {component} =
               Ecspanse.Query.select({TestComponent1}, for: [entity])
               |> Ecspanse.Query.one(token)

      assert entity == Ecspanse.Query.get_component_entity(component, token)
    end
  end

  describe "list_children/2" do
    test "returns the children of an entity" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

      entity_1 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, []})

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, []})

      entity_3 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, children: [entity_1, entity_2]})

      assert [entity_1, entity_2] == Ecspanse.Query.list_children(entity_3, token)
    end
  end

  describe "list_parents/2" do
    test "returns the parents of an entity" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

      entity_1 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, []})

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [entity_1]})

      entity_3 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, children: [entity_2]})

      assert [entity_1, entity_3] == Ecspanse.Query.list_parents(entity_2, token)
    end
  end

  describe "list_group_components/2" do
    test "returns the components of a group" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

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

      components = Ecspanse.Query.list_group_components(:foo, token)

      assert length(components) == 4

      for %comp_module{} <- components do
        assert comp_module in [TestComponent4, TestComponent5]
      end
    end
  end

  describe "list_group_components/3" do
    test "returns the components of a group for a given entity" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

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

      components = Ecspanse.Query.list_group_components(entity_1, :bar, token)

      assert length(components) == 1

      assert [%TestComponent4{}] = components
    end
  end

  describe "fetch_component/3" do
    test "returns a component for a given entity" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [TestComponent1, TestComponent2, TestComponent4, TestComponent5]}
        )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent4]}
      )

      assert {:ok, %TestComponent1{} = component} =
               Ecspanse.Query.fetch_component(entity_1, TestComponent1, token)

      entity = Ecspanse.Query.get_component_entity(component, token)
      assert entity == entity_1
    end
  end

  describe "fetch_components/3" do
    test "returns a tuple of components if the entity has all of them" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [TestComponent1, TestComponent2, TestComponent4, TestComponent5]}
        )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent4]}
      )

      assert {:ok, {%TestComponent1{} = component_1, %TestComponent4{} = component_2}} =
               Ecspanse.Query.fetch_components(entity_1, {TestComponent1, TestComponent4}, token)

      entity = Ecspanse.Query.get_component_entity(component_1, token)
      assert entity == entity_1

      entity = Ecspanse.Query.get_component_entity(component_2, token)
      assert entity == entity_1
    end
  end

  describe "is_type?/3" do
    test "checks if an entity has a certain entity_type component" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5]}
        )

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert Ecspanse.Query.is_type?(entity_1, TestComponent5, token)
      refute Ecspanse.Query.is_type?(entity_2, TestComponent5, token)
    end
  end

  describe "has_component?/3" do
    test "checks if an entity has a certain component" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5]}
        )

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert Ecspanse.Query.has_component?(entity_1, TestComponent5, token)
      refute Ecspanse.Query.has_component?(entity_2, TestComponent5, token)
    end
  end

  describe "has_components?/3" do
    test "check if an entity has all of the given components" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5]}
        )

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert Ecspanse.Query.has_components?(entity_1, [TestComponent1, TestComponent5], token)
      refute Ecspanse.Query.has_components?(entity_2, [TestComponent1, TestComponent5], token)
    end
  end

  describe "has_children_with_type?/3" do
    test "checks if an entity has children with a certain entity_type component" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5]}
        )

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5], children: [entity_1]}
        )

      refute Ecspanse.Query.has_children_with_type?(entity_1, TestComponent5, token)
      assert Ecspanse.Query.has_children_with_type?(entity_2, TestComponent5, token)
    end
  end

  describe "has_children_with_component?/3" do
    test "checks if an entity has children with a certain component" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5]}
        )

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1], children: [entity_1]}
        )

      refute Ecspanse.Query.has_children_with_component?(entity_1, TestComponent1, token)
      assert Ecspanse.Query.has_children_with_component?(entity_2, TestComponent1, token)
    end
  end

  describe "has_children_with_components?/3" do
    test "checks if an entity has children with all of the given components" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

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
               [TestComponent1, TestComponent5],
               token
             )

      assert Ecspanse.Query.has_children_with_components?(
               entity_2,
               [TestComponent1, TestComponent5],
               token
             )
    end
  end

  describe "has_parents_with_type?/3" do
    test "checks if an entity has parents with a certain entity_type component" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5]}
        )

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5], parents: [entity_1]}
        )

      refute Ecspanse.Query.has_parents_with_type?(entity_1, TestComponent5, token)
      assert Ecspanse.Query.has_parents_with_type?(entity_2, TestComponent5, token)
    end
  end

  describe "has_parents_with_component?/3" do
    test "checks if an entity has parents with a certain component" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5]}
        )

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1], parents: [entity_1]}
        )

      refute Ecspanse.Query.has_parents_with_component?(entity_1, TestComponent1, token)
      assert Ecspanse.Query.has_parents_with_component?(entity_2, TestComponent1, token)
    end
  end

  describe "has_parents_with_components?/3" do
    test "checks if an entity has parents with all of the given components" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5]}
        )

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent5], parents: [entity_1]}
        )

      refute Ecspanse.Query.has_parents_with_components?(
               entity_1,
               [TestComponent1, TestComponent5],
               token
             )

      assert Ecspanse.Query.has_parents_with_components?(
               entity_2,
               [TestComponent1, TestComponent5],
               token
             )
    end
  end

  describe "fetch_resource/2" do
    test "fetches a resource from the world" do
      assert {:ok, token} = Ecspanse.new(TestWorld1)
      Ecspanse.System.debug(token)

      resource = Ecspanse.Command.insert_resource!(TestResource1)

      assert {:ok, ^resource} = Ecspanse.Query.fetch_resource(TestResource1, token)
    end
  end
end
