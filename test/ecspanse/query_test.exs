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
    use Ecspanse.Component, tags: [:foo, :bar]
  end

  defmodule TestComponent5 do
    @moduledoc false
    use Ecspanse.Component, tags: [:baz]
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
    start_supervised({TestServer1, :test})
    Ecspanse.Server.test_server(self())
    # # simulate commands are run from a System
    Ecspanse.System.debug()

    :ok
  end

  describe "select/2" do
    test "returns components for entities with all components" do
      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity,
         components: [{TestComponent1, [], [:tag1]}, TestComponent2, TestComponent3]}
      )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity,
         components: [TestComponent1, {TestComponent2, [], [:tag2]}, TestComponent3]}
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

    test "can query just descendants of entities" do
      entity_1 =
        Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1], parents: [entity_1]}
        )

      entity_3 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1], parents: [entity_2]}
        )

      assert result =
               Ecspanse.Query.select({Ecspanse.Entity, TestComponent1},
                 for_descendants_of: [entity_1]
               )
               |> Ecspanse.Query.stream()
               |> Enum.to_list()

      assert length(result) == 2

      for {entity, component} <- result do
        assert entity.id in [entity_2.id, entity_3.id]
        assert %TestComponent1{} = component
      end
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

    test "can query just ancestors of entities" do
      entity_1 =
        Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1], parents: [entity_1]}
        )

      entity_3 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1], parents: [entity_2]}
        )

      assert result =
               Ecspanse.Query.select({Ecspanse.Entity, TestComponent1},
                 for_ancestors_of: [entity_3]
               )
               |> Ecspanse.Query.stream()
               |> Enum.to_list()

      assert length(result) == 2

      for {entity, component} <- result do
        assert entity.id in [entity_1.id, entity_2.id]
        assert %TestComponent1{} = component
      end
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

  describe "fetch_entity/1" do
    test "returns the entity for a component" do
      entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert {:ok, ^entity} = Ecspanse.Query.fetch_entity(entity.id)
    end

    test "returns error if the entity does not exist" do
      assert {:error, :not_found} = Ecspanse.Query.fetch_entity(UUID.uuid4())
    end
  end

  describe "get_component_entity/1" do
    test "returns the entity for a component" do
      entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert {component} =
               Ecspanse.Query.select({TestComponent1}, for: [entity])
               |> Ecspanse.Query.one()

      assert entity == Ecspanse.Query.get_component_entity(component)
    end
  end

  describe "list_children/1" do
    test "returns the children of an entity" do
      entity_1 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, [components: [TestComponent1]]})

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, [components: [TestComponent1]]})

      entity_3 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, children: [entity_1, entity_2]})

      assert [entity_1, entity_2] == Ecspanse.Query.list_children(entity_3)
    end
  end

  describe "list_descendants/1" do
    test "returns the descendants of an entity" do
      entity_1 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, children: [entity_1]})

      entity_3 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, children: [entity_2]})

      assert [entity_2, entity_1] == Ecspanse.Query.list_descendants(entity_3)
    end
  end

  describe "list_parents/1" do
    test "returns the parents of an entity" do
      entity_1 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, [components: [TestComponent1]]})

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [entity_1]})

      entity_3 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, children: [entity_2]})

      assert [entity_1, entity_3] == Ecspanse.Query.list_parents(entity_2)
    end
  end

  describe "list_ancestors/1" do
    test "returns the ancestors of an entity" do
      entity_1 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, children: [entity_1]})

      entity_3 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, children: [entity_2]})

      assert [entity_2, entity_3] == Ecspanse.Query.list_ancestors(entity_1)
    end
  end

  describe "fetch_tagged_component" do
    test "fetches one entity's component by its tags" do
      entity =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [
             TestComponent1,
             TestComponent2,
             {TestComponent4, [], [:unique]},
             TestComponent5
           ]}
        )

      assert {:ok, %TestComponent4{}} =
               Ecspanse.Query.fetch_tagged_component(entity, [:unique])
    end
  end

  describe "list_tags" do
    test "returns the tags for a component" do
      entity =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [
             {TestComponent4, [], [:baz]}
           ]}
        )

      {:ok, component} = TestComponent4.fetch(entity)

      assert [:foo, :bar, :baz] == Ecspanse.Query.list_tags(component)
    end
  end

  describe "list_tagged_components/1" do
    test "returns the components for a list of tags" do
      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity,
         components: [
           TestComponent1,
           TestComponent2,
           TestComponent4,
           {TestComponent5, [], [:foo]}
         ]}
      )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent4]}
      )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent3, {TestComponent5, [], [:foo]}]}
      )

      components = Ecspanse.Query.list_tagged_components([:foo])

      assert length(components) == 4

      for %comp_module{} <- components do
        assert comp_module in [TestComponent4, TestComponent5]
      end
    end
  end

  describe "list_tagged_components_for_entity/2" do
    test "returns the components for a list of tags for a given entity" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [
             TestComponent1,
             TestComponent2,
             {TestComponent4, [], [:alpha]},
             TestComponent5
           ]}
        )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity, components: [TestComponent1, TestComponent4]}
      )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity,
         components: [
           {TestComponent4, [], [:alpha]}
         ]}
      )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity,
         components: [TestComponent3, {TestComponent4, [], [:alpha]}, TestComponent5]}
      )

      components = Ecspanse.Query.list_tagged_components_for_entity(entity_1, [:bar, :alpha])

      assert length(components) == 1

      assert [%TestComponent4{} = comp] = components
      e = Ecspanse.Query.get_component_entity(comp)
      assert e.id == entity_1.id
    end
  end

  describe "list_tagged_components_for_entities/2" do
    test "returns the components for a list of tags for a given entity" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [
             TestComponent1,
             TestComponent2,
             {TestComponent4, [], [:alpha]},
             TestComponent5
           ]}
        )

      entity_2 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent4]}
        )

      entity_3 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [
             {TestComponent4, [], [:alpha]}
           ]}
        )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity,
         components: [TestComponent3, {TestComponent4, [], [:alpha]}, TestComponent5]}
      )

      components =
        Ecspanse.Query.list_tagged_components_for_entities([entity_1, entity_2, entity_3], [
          :bar,
          :alpha
        ])

      assert length(components) == 2

      assert [%TestComponent4{} = comp_1, %TestComponent4{} = comp_2] = components
      e1 = Ecspanse.Query.get_component_entity(comp_1)
      e2 = Ecspanse.Query.get_component_entity(comp_2)
      assert Enum.all?([e1, e2], fn e -> e.id in [entity_1.id, entity_3.id] end)
    end
  end

  describe "list_tagged_components_for_children/2" do
    test "returns the components for a list of tags for the children of a given entity" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [
             TestComponent1,
             TestComponent2,
             {TestComponent4, [], [:alpha]},
             TestComponent5
           ]}
        )

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, children: [entity_1]})

      entity_3 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [{TestComponent4, [], [:alpha]}], parents: [entity_2]}
        )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity,
         components: [TestComponent3, {TestComponent4, [], [:alpha]}, TestComponent5]}
      )

      components = Ecspanse.Query.list_tagged_components_for_children(entity_2, [:bar, :alpha])

      assert length(components) == 2

      assert [%TestComponent4{} = comp_1, %TestComponent4{} = comp_2] = components
      e1 = Ecspanse.Query.get_component_entity(comp_1)
      e2 = Ecspanse.Query.get_component_entity(comp_2)
      assert Enum.all?([e1, e2], fn e -> e.id in [entity_1.id, entity_3.id] end)
    end
  end

  describe "list_tagged_components_for_descendants/2" do
    test "returns the components for a list of tags for the descendants of a given entity" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [
             TestComponent1,
             TestComponent2,
             {TestComponent4, [], [:alpha]},
             TestComponent5
           ]}
        )

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, children: [entity_1]})

      entity_3 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [{TestComponent4, [], [:alpha]}], parents: [entity_1]}
        )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity,
         components: [TestComponent3, {TestComponent4, [], [:alpha]}, TestComponent5]}
      )

      components = Ecspanse.Query.list_tagged_components_for_descendants(entity_2, [:bar, :alpha])

      assert length(components) == 2

      assert [%TestComponent4{} = comp_1, %TestComponent4{} = comp_2] = components
      e1 = Ecspanse.Query.get_component_entity(comp_1)
      e2 = Ecspanse.Query.get_component_entity(comp_2)
      assert Enum.all?([e1, e2], fn e -> e.id in [entity_1.id, entity_3.id] end)
    end
  end

  describe "list_tagged_components_for_parents/2" do
    test "returns the components for a list of tags for the parents of a given entity" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [
             TestComponent1,
             TestComponent2,
             {TestComponent4, [], [:alpha]},
             TestComponent5
           ]}
        )

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [entity_1]})

      entity_3 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [{TestComponent4, [], [:alpha]}], children: [entity_2]}
        )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity,
         components: [TestComponent3, {TestComponent4, [], [:alpha]}, TestComponent5]}
      )

      components = Ecspanse.Query.list_tagged_components_for_parents(entity_2, [:bar, :alpha])

      assert length(components) == 2

      assert [%TestComponent4{} = comp_1, %TestComponent4{} = comp_2] = components
      e1 = Ecspanse.Query.get_component_entity(comp_1)
      e2 = Ecspanse.Query.get_component_entity(comp_2)
      assert Enum.all?([e1, e2], fn e -> e.id in [entity_1.id, entity_3.id] end)
    end
  end

  describe "list_tagged_components_for_ancestors/2" do
    test "returns the components for a list of tags for the ancestors of a given entity" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [
             TestComponent1,
             TestComponent2,
             {TestComponent4, [], [:alpha]},
             TestComponent5
           ]}
        )

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [entity_1]})

      entity_3 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [{TestComponent4, [], [:alpha]}], children: [entity_1]}
        )

      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity,
         components: [TestComponent3, {TestComponent4, [], [:alpha]}, TestComponent5]}
      )

      components = Ecspanse.Query.list_tagged_components_for_ancestors(entity_2, [:bar, :alpha])

      assert length(components) == 2

      assert [%TestComponent4{} = comp_1, %TestComponent4{} = comp_2] = components
      e1 = Ecspanse.Query.get_component_entity(comp_1)
      e2 = Ecspanse.Query.get_component_entity(comp_2)
      assert Enum.all?([e1, e2], fn e -> e.id in [entity_1.id, entity_3.id] end)
    end
  end

  describe "fetch_component/2" do
    test "returns a component for a given entity" do
      entity_1 =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity,
           components: [
             {TestComponent1, [], [:tag1]},
             TestComponent2,
             TestComponent4,
             TestComponent5
           ]}
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

  describe "fetch_components/2" do
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

  describe "list_components/1" do
    test "returns a list with all entity's components" do
      component_modules = [TestComponent1, TestComponent2, TestComponent4, TestComponent5]

      entity =
        Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: component_modules})

      components = Ecspanse.Query.list_components(entity)

      assert length(components) == length(component_modules)

      for component <- components do
        assert component.__struct__ in component_modules
      end
    end
  end

  describe "has_component?/2" do
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

  describe "has_components?/2" do
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

  describe "is_child_of/2, is_parent_of/2" do
    test "checks if there is a relation between 2 entities" do
      entity_1 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, [components: [TestComponent1]]})

      entity_2 = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, parents: [entity_1]})

      assert Ecspanse.Query.is_child_of?(parent: entity_1, child: entity_2)
      refute Ecspanse.Query.is_child_of?(parent: entity_2, child: entity_1)

      assert Ecspanse.Query.is_parent_of?(parent: entity_1, child: entity_2)
      refute Ecspanse.Query.is_parent_of?(parent: entity_2, child: entity_1)
    end
  end

  describe "has_children_with_component?/2" do
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

  describe "has_children_with_components?/2" do
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

  describe "has_parents_with_component?/2" do
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

  describe "has_parents_with_components?/2" do
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

  describe "fetch_resource/1" do
    test "fetches a resource" do
      resource = Ecspanse.Command.insert_resource!(TestResource1)

      assert {:ok, ^resource} = Ecspanse.Query.fetch_resource(TestResource1)
    end
  end
end
