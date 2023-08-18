defmodule Ecspanse.Template.ComponentTest do
  use ExUnit.Case

  defmodule TestComponentTemplate do
    @moduledoc false
    use Ecspanse.Template.Component, state: [:foo, bar: 2], tags: [:alpha]
  end

  defmodule TestComponent1 do
    @moduledoc false
    use TestComponentTemplate, state: [foo: 5]
  end

  defmodule TestComponent2 do
    @moduledoc false
    use TestComponentTemplate,
      state: [foo: 1, bar: 3, baz: 9],
      tags: [:beta]
  end

  defmodule TestServer do
    @moduledoc false
    use Ecspanse

    def setup(data) do
      data
    end
  end

  setup do
    start_supervised({TestServer, :test})
    Ecspanse.Server.test_server(self())
    # simulate commands are run from a System
    Ecspanse.System.debug()

    :ok
  end

  test "component template provides a default state for the components using it" do
    entity =
      Ecspanse.Command.spawn_entity!(
        {Ecspanse.Entity,
         components: [
           TestComponent1,
           {TestComponent2, [foo: 7], [:gamma]}
         ]}
      )

    assert {:ok, %TestComponent1{foo: 5, bar: 2}} = TestComponent1.fetch(entity)
    assert {:ok, %TestComponent2{foo: 7, bar: 3, baz: 9}} = TestComponent2.fetch(entity)

    components = Ecspanse.Query.list_tagged_components_for_entity(entity, [:alpha])
    assert length(components) == 2

    components = Ecspanse.Query.list_tagged_components_for_entity(entity, [:alpha, :beta, :gamma])
    assert length(components) == 1
  end
end
