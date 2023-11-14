defmodule Ecspanse.ProjectionTest do
  use ExUnit.Case

  alias Ecspanse.Projection

  defmodule TestComponent1 do
    @moduledoc false
    use Ecspanse.Component, state: [value: 1]
  end

  defmodule TestComponent2 do
    @moduledoc false
    use Ecspanse.Component, state: [value: 2]
  end

  defmodule TestProjection do
    @moduledoc false
    use Ecspanse.Projection, fields: [comp_1: 0, comp_2: 0]

    @impl true
    def project(%{entity_id: entity_id}) do
      with {:ok, entity} <- fetching_entity(entity_id),
           {:ok, comp_1} <- fetching_first_component(entity),
           {:ok, comp_2} <- fetching_second_component(entity) do
        result = struct!(__MODULE__, comp_1: comp_1.value, comp_2: comp_2.value)
        {:ok, result}
      end
    end

    # if the entity is not found, the projection is in :loading state
    defp fetching_entity(entity_id) do
      case Ecspanse.Entity.fetch(entity_id) do
        {:ok, entity} -> {:ok, entity}
        _ -> :loading
      end
    end

    # if comp_1 is not present for the entity it is considered an error
    defp fetching_first_component(entity) do
      case TestComponent1.fetch(entity) do
        {:ok, comp_1} -> {:ok, comp_1}
        _ -> {:error, :comp_1_not_found}
      end
    end

    # if comp_2 is not present for the entity, the projection will halt
    defp fetching_second_component(entity) do
      case TestComponent2.fetch(entity) do
        {:ok, comp_2} -> {:ok, comp_2}
        _ -> :halt
      end
    end

    @impl true
    def on_change(%{test_pid: test_pid}, projection, _previous_projection) do
      send(test_pid, {:projection_updated, projection})
    end
  end

  defmodule TestServer do
    @moduledoc false
    use Ecspanse, fps_limit: 12

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

  describe "get!/1" do
    test "returns the projection" do
      entity =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2]}
        )

      assert_receive {:next_frame, _state}

      projection_pid = TestProjection.start!(%{entity_id: entity.id, test_pid: self()})

      assert %Projection{state: :ok, result: %TestProjection{comp_1: 1, comp_2: 2}} =
               TestProjection.get!(projection_pid)

      assert_receive {:next_frame, _state}

      {:ok, comp_1} = TestComponent1.fetch(entity)
      {:ok, comp_2} = TestComponent2.fetch(entity)

      Ecspanse.Command.update_components!([{comp_1, value: 100}, {comp_2, value: 200}])

      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, _state}

      assert %Projection{state: :ok, result: %TestProjection{comp_1: 100, comp_2: 200}} =
               TestProjection.get!(projection_pid)

      TestProjection.stop(projection_pid)
    end
  end

  describe "on_change/3" do
    test "is called once when the projection server starts" do
      entity =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2]}
        )

      assert_receive {:next_frame, _state}

      projection_pid = TestProjection.start!(%{entity_id: entity.id, test_pid: self()})

      assert %Projection{state: :ok, result: %TestProjection{comp_1: 1, comp_2: 2}} =
               TestProjection.get!(projection_pid)

      assert_receive {:next_frame, _state}

      assert_receive {:projection_updated,
                      %Projection{state: :ok, result: %TestProjection{comp_1: 1, comp_2: 2}}}

      TestProjection.stop(projection_pid)
    end

    test "is called when the projection changes" do
      entity =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2]}
        )

      assert_receive {:next_frame, _state}

      projection_pid = TestProjection.start!(%{entity_id: entity.id, test_pid: self()})

      assert %Projection{state: :ok, result: %TestProjection{comp_1: 1, comp_2: 2}} =
               TestProjection.get!(projection_pid)

      assert_receive {:next_frame, _state}

      {:ok, comp_1} = TestComponent1.fetch(entity)
      {:ok, comp_2} = TestComponent2.fetch(entity)

      Ecspanse.Command.update_components!([{comp_1, value: 100}, {comp_2, value: 200}])

      assert_receive {:next_frame, _state}

      assert_receive {:projection_updated,
                      %Projection{state: :ok, result: %TestProjection{comp_1: 100, comp_2: 200}}}

      TestProjection.stop(projection_pid)
    end
  end

  describe "projection states" do
    test "the projection is in :loading state when the entity does not exist" do
      projection_pid = TestProjection.start!(%{entity_id: "not ready", test_pid: self()})

      assert %Projection{
               state: :loading,
               result: nil,
               loading?: true,
               ok?: false,
               error?: false,
               halted?: false
             } =
               TestProjection.get!(projection_pid)
    end

    test "the projection is in :error state if the component_1 does not exist" do
      entity =
        Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [TestComponent2]})

      assert_receive {:next_frame, _state}

      projection_pid = TestProjection.start!(%{entity_id: entity.id, test_pid: self()})

      assert %Projection{
               state: :error,
               result: :comp_1_not_found,
               loading?: false,
               ok?: false,
               error?: true,
               halted?: false
             } =
               TestProjection.get!(projection_pid)

      assert_receive {:next_frame, _state}

      Ecspanse.Command.add_component!(entity, TestComponent1)

      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, _state}

      assert %Projection{
               state: :ok,
               result: %TestProjection{comp_1: 1, comp_2: 2},
               loading?: false,
               ok?: true,
               error?: false,
               halted?: false
             } =
               TestProjection.get!(projection_pid)
    end

    test "the projection is in :halt state if the component_2 does not exist" do
      entity =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2]}
        )

      {:ok, comp_1} = TestComponent1.fetch(entity)
      {:ok, comp_2} = TestComponent2.fetch(entity)

      assert_receive {:next_frame, _state}

      projection_pid = TestProjection.start!(%{entity_id: entity.id, test_pid: self()})

      assert %Projection{state: :ok, result: %TestProjection{comp_1: 1, comp_2: 2}} =
               TestProjection.get!(projection_pid)

      assert_receive {:next_frame, _state}

      Ecspanse.Command.remove_component!(comp_2)

      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, _state}

      assert %Projection{
               state: :halt,
               result: %TestProjection{comp_1: 1, comp_2: 2},
               loading?: false,
               ok?: false,
               error?: false,
               halted?: true
             } =
               TestProjection.get!(projection_pid)

      # Even if the Ecspanse components change, while waiting, the projection does not change.
      # This is useful for complex projections that should run only when the entity is in a certain state.

      Ecspanse.Command.update_component!(comp_1, value: 100)

      assert_receive {:next_frame, _state}

      assert %Projection{state: :halt, result: %TestProjection{comp_1: 1, comp_2: 2}} =
               TestProjection.get!(projection_pid)

      assert_receive {:next_frame, _state}

      {:ok, comp_1} = TestComponent1.fetch(entity)
      Ecspanse.Command.update_component!(comp_1, value: 200)

      assert_receive {:next_frame, _state}

      assert %Projection{state: :halt, result: %TestProjection{comp_1: 1, comp_2: 2}} =
               TestProjection.get!(projection_pid)

      assert_receive {:next_frame, _state}

      Ecspanse.Command.add_component!(entity, TestComponent2)

      assert_receive {:next_frame, _state}

      # once back to :ok state, it will return the processed projection

      assert %Projection{
               state: :ok,
               result: %TestProjection{comp_1: 200, comp_2: 2},
               loading?: false,
               ok?: true,
               error?: false,
               halted?: false
             } =
               TestProjection.get!(projection_pid)
    end
  end
end
