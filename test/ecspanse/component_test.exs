defmodule Ecspanse.ComponentTest do
  use ExUnit.Case

  defmodule TestComponent1 do
    @moduledoc false
    use Ecspanse.Component
  end

  defmodule TestComponent2 do
    @moduledoc false
    use Ecspanse.Component, state: [value: :foo]

    def validate(%TestComponent2{value: value}) do
      if value == :foo do
        :ok
      else
        {:error, "Invalid value"}
      end
    end
  end

  defmodule TestServer1 do
    @moduledoc false
    use Ecspanse

    def setup(data) do
      data
    end
  end

  ######

  setup do
    start_supervised({TestServer1, :test})
    Ecspanse.Server.test_server(self())
    # simulate commands are run from a System
    Ecspanse.System.debug()

    :ok
  end

  describe "fetch/1" do
    test "returns the component for the current module for a given entity" do
      entity_1 =
        Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert {:ok, %TestComponent1{} = component} =
               TestComponent1.fetch(entity_1)

      entity = Ecspanse.Query.get_component_entity(component)
      assert entity == entity_1
    end
  end

  describe "list/0" do
    test "returns all components for the current component module, for all entities" do
      Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})
      Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent1]})

      assert [%TestComponent1{}, %TestComponent1{}] = TestComponent1.list()
    end
  end

  describe "validate/1 callback" do
    test "raises an Ecspanse.Command.Error if the component is invalid at creation time" do
      assert_raise(Ecspanse.Command.Error, fn ->
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [{TestComponent2, value: :bar}]}
        )
      end)
    end

    test "raises an Ecspanse.Command.Error if the component is invalid upon update" do
      entity =
        Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent2]})

      {:ok, component} = TestComponent2.fetch(entity)

      assert_raise(Ecspanse.Command.Error, fn ->
        Ecspanse.Command.update_component!(component, value: :bar)
      end)
    end
  end
end
