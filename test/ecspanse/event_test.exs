defmodule Ecspanse.EventTest do
  use ExUnit.Case

  defmodule Counter do
    @moduledoc false

    use Ecspanse.Component, state: [value: 0]
  end

  defmodule ParentProcess do
    @moduledoc false
    use Ecspanse.Resource, state: [:pid]
  end

  defmodule IncrementEvent do
    @moduledoc false
    use Ecspanse.Event, fields: [:entity_id]
  end

  defmodule ReadyEvent do
    @moduledoc false
    use Ecspanse.Event
  end

  defmodule IncrementSystem do
    @moduledoc false
    use Ecspanse.System,
      event_subscriptions: [IncrementEvent],
      lock_components: [Counter]

    @impl true
    def run(%IncrementEvent{entity_id: entity_id}, _frame) do
      with {:ok, entity} <- Ecspanse.Query.fetch_entity(entity_id),
           {:ok, %Counter{value: value} = component} <- Counter.fetch(entity) do
        Ecspanse.Command.update_component!(component, value: value + 1)
      end
    end
  end

  defmodule ReadySystem do
    @moduledoc false
    use Ecspanse.System,
      event_subscriptions: [ReadyEvent]

    @impl true
    def run(%ReadyEvent{}, _frame) do
      {:ok, %ParentProcess{pid: pid}} = Ecspanse.Query.fetch_resource(ParentProcess)
      send(pid, :ready)
    end
  end

  defmodule TestServer1 do
    @moduledoc false
    use Ecspanse, fps_limit: 10

    @impl true
    def setup(data) do
      data
      |> Ecspanse.add_system(IncrementSystem)
      |> Ecspanse.add_frame_end_system(ReadySystem)
    end
  end

  defmodule TestServer2 do
    @moduledoc false
    use Ecspanse

    @impl true
    def setup(data) do
      data
      |> Ecspanse.add_system(IncrementSystem)
      |> Ecspanse.add_frame_end_system(ReadySystem)
    end
  end

  test "processes many events per frame" do
    start_supervised({TestServer1, :test})
    Ecspanse.Server.test_server(self())
    # simulate commands are run from a System
    Ecspanse.System.debug()

    Ecspanse.Command.insert_resource!({ParentProcess, pid: self()})

    entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [Counter]})
    assert {:ok, %Counter{value: 0}} = Counter.fetch(entity)

    for _ <- 1..1000 do
      Ecspanse.event({IncrementEvent, entity_id: entity.id}, batch_key: entity.id)
    end

    Ecspanse.event(ReadyEvent)

    assert_receive :ready, 2000
    assert_receive {:next_frame, _state}
    assert {:ok, %Counter{value: 1000}} = Counter.fetch(entity)
  end

  @tag timeout: :infinity
  test "processes many events in many frames" do
    start_supervised({TestServer2, :test})
    Ecspanse.Server.test_server(self())
    # simulate commands are run from a System
    Ecspanse.System.debug()

    Ecspanse.Command.insert_resource!({ParentProcess, pid: self()})

    entity = Ecspanse.Command.spawn_entity!({Ecspanse.Entity, components: [Counter]})
    assert {:ok, %Counter{value: 0}} = Counter.fetch(entity)

    for _ <- 1..1000 do
      Ecspanse.event({IncrementEvent, entity_id: entity.id}, batch_key: entity.id)
    end

    Ecspanse.event(ReadyEvent)

    assert_receive :ready, 2000
    assert_receive {:next_frame, _state}

    assert {:ok, %Counter{value: 1000}} = Counter.fetch(entity)
  end
end
