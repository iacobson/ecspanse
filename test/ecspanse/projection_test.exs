defmodule Ecspanse.ProjectionTest do
  use ExUnit.Case

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
    def run?(%{entity_id: entity_id}, _projection) do
      {:ok, entity} = fetch_entity(entity_id)
      {:ok, comp_1} = TestComponent1.fetch(entity)
      {:ok, comp_2} = TestComponent2.fetch(entity)

      comp_1.value > 0 && comp_2.value > 0
    end

    @impl true
    def project(%{entity_id: entity_id}) do
      {:ok, entity} = fetch_entity(entity_id)
      {:ok, comp_1} = TestComponent1.fetch(entity)
      {:ok, comp_2} = TestComponent2.fetch(entity)

      struct!(__MODULE__, comp_1: comp_1.value, comp_2: comp_2.value)
    end

    @impl true
    def on_change(%{test_pid: test_pid}, projection, _previous_projection) do
      send(test_pid, {:projection_updated, projection})
    end
  end

  defmodule TestServer do
    @moduledoc false
    use Ecspanse, fps_limit: 60

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

      assert %TestProjection{comp_1: 1, comp_2: 2} = TestProjection.get!(projection_pid)

      assert_receive {:next_frame, _state}

      {:ok, comp_1} = TestComponent1.fetch(entity)
      {:ok, comp_2} = TestComponent2.fetch(entity)

      Ecspanse.Command.update_components!([{comp_1, value: 100}, {comp_2, value: 200}])

      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, _state}

      assert %TestProjection{comp_1: 100, comp_2: 200} = TestProjection.get!(projection_pid)

      TestProjection.stop(projection_pid)
    end
  end

  describe "run?/2" do
    test "runs the projection only in the correct state" do
      # the projection would not run if one of the components values is <= 0

      entity =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2]}
        )

      assert_receive {:next_frame, _state}

      projection_pid = TestProjection.start!(%{entity_id: entity.id, test_pid: self()})

      assert %TestProjection{comp_1: 1, comp_2: 2} = TestProjection.get!(projection_pid)

      assert_receive {:next_frame, _state}

      {:ok, comp_1} = TestComponent1.fetch(entity)
      {:ok, comp_2} = TestComponent2.fetch(entity)

      Ecspanse.Command.update_components!([{comp_1, value: 100}, {comp_2, value: 200}])

      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, _state}

      assert %TestProjection{comp_1: 100, comp_2: 200} = TestProjection.get!(projection_pid)

      # update components to negative values
      Ecspanse.Command.update_components!([{comp_1, value: -999}, {comp_2, value: -999}])

      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, _state}

      assert %TestProjection{comp_1: 100, comp_2: 200} = TestProjection.get!(projection_pid)

      Ecspanse.Command.update_components!([{comp_1, value: 10}, {comp_2, value: 20}])

      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, _state}

      assert %TestProjection{comp_1: 10, comp_2: 20} = TestProjection.get!(projection_pid)

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
      assert %TestProjection{comp_1: 1, comp_2: 2} = TestProjection.get!(projection_pid)

      assert_receive {:next_frame, _state}

      assert_receive {:projection_updated, %TestProjection{comp_1: 1, comp_2: 2}}
      TestProjection.stop(projection_pid)
    end

    test "is called when the projection changes" do
      entity =
        Ecspanse.Command.spawn_entity!(
          {Ecspanse.Entity, components: [TestComponent1, TestComponent2]}
        )

      assert_receive {:next_frame, _state}

      projection_pid = TestProjection.start!(%{entity_id: entity.id, test_pid: self()})
      assert %TestProjection{comp_1: 1, comp_2: 2} = TestProjection.get!(projection_pid)

      assert_receive {:next_frame, _state}

      {:ok, comp_1} = TestComponent1.fetch(entity)
      {:ok, comp_2} = TestComponent2.fetch(entity)

      Ecspanse.Command.update_components!([{comp_1, value: 100}, {comp_2, value: 200}])

      assert_receive {:next_frame, _state}

      assert_receive {:projection_updated, %TestProjection{comp_1: 100, comp_2: 200}}
      TestProjection.stop(projection_pid)
    end
  end
end
