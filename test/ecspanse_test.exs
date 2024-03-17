defmodule EcspanseTest do
  use ExUnit.Case

  defmodule TestStartupEvent do
    @moduledoc false
    use Ecspanse.Event, fields: [:data, :pid]
  end

  defmodule TetsEvent1 do
    @moduledoc false
    use Ecspanse.Event
  end

  defmodule TetsEvent2 do
    @moduledoc false
    use Ecspanse.Event
  end

  defmodule TestStartupSystem do
    @moduledoc false
    use Ecspanse.System,
      event_subscriptions: [TestStartupEvent]

    @impl true
    def run(%TestStartupEvent{} = event, _frame) do
      send(event.pid, {:startup, event.data})
    end
  end

  defmodule TestRunningSystem do
    @moduledoc false
    use Ecspanse.System,
      event_subscriptions: [TestStartupEvent]

    @impl true
    def run(%TestStartupEvent{} = event, _frame) do
      # this should never happen
      # the TestStartupEvent should run only on startup
      send(event.pid, {:running, event.data})
    end
  end

  defmodule TestServer0 do
    @moduledoc false
    use Ecspanse, fps_limit: 60

    @impl true
    def setup(data) do
      data
      |> add_startup_system(TestStartupSystem)
      |> add_frame_start_system(TestRunningSystem)
    end
  end

  #########

  defmodule TestSystem1 do
    @moduledoc false
    use Ecspanse.System

    def run(_frame), do: :ok
  end

  defmodule TestSystem2 do
    @moduledoc false
    use Ecspanse.System

    def run(_frame), do: :ok
  end

  defmodule TestSystem3 do
    @moduledoc false
    use Ecspanse.System

    def run(_frame), do: :ok
  end

  defmodule TestSystem4 do
    @moduledoc false
    use Ecspanse.System

    def run(_frame), do: :ok
  end

  defmodule TestSystem5 do
    @moduledoc false
    use Ecspanse.System

    def run(_frame), do: :ok
  end

  defmodule TestServer1 do
    @moduledoc false
    use Ecspanse

    def setup(data) do
      data
      |> add_system(TestSystem5)
      |> add_frame_end_system(TestSystem3)
      |> add_frame_start_system(TestSystem2)
      |> add_startup_system(TestSystem1)
      |> add_shutdown_system(TestSystem4)
    end
  end

  ##########

  defmodule TestComponent1 do
    @moduledoc false
    use Ecspanse.Component
  end

  defmodule TestSystem6 do
    @moduledoc false
    use Ecspanse.System, lock_components: [TestComponent1]

    def run(_frame), do: :ok
  end

  defmodule TestSystem7 do
    @moduledoc false
    use Ecspanse.System, lock_components: [TestComponent1]

    def run(_frame), do: :ok
  end

  defmodule TestSystem8 do
    @moduledoc false
    use Ecspanse.System

    def run(_frame), do: :ok
  end

  defmodule TestServer2 do
    @moduledoc false
    use Ecspanse

    def setup(data) do
      data
      |> add_system(TestSystem6)
      |> add_system(TestSystem7)
      |> add_system(TestSystem8)
    end
  end

  ##########

  defmodule TestServer3 do
    @moduledoc false
    use Ecspanse

    def setup(data) do
      data
      |> Ecspanse.add_system_set({__MODULE__, :test_system_set})
    end

    def test_system_set(data) do
      data
      |> add_system(TestSystem1)
      |> add_system(TestSystem2)
    end
  end

  ##########

  defmodule TestServer4 do
    @moduledoc false
    use Ecspanse

    def setup(data) do
      data
      |> add_system(TestSystem6)
      |> add_system(TestSystem8, run_after: [TestSystem6])
      |> add_system(TestSystem7)
    end
  end

  ##########

  defmodule TestResource1 do
    @moduledoc false
    use Ecspanse.Resource, state: [pid: nil]
  end

  defmodule TestSystem9 do
    @moduledoc false
    use Ecspanse.System

    def run(_frame) do
      insert_resource!(TestResource1)
    end
  end

  defmodule TestSystem10 do
    @moduledoc false
    use Ecspanse.System

    def run(_frame) do
      {:ok, resource} = fetch_resource(TestResource1)
      send(resource.pid, :foo)
    end
  end

  defmodule TestSystem11 do
    @moduledoc false
    use Ecspanse.System

    def run(_frame) do
      {:ok, resource} = fetch_resource(TestResource1)
      send(resource.pid, :bar)
    end
  end

  defmodule TestServer5 do
    @moduledoc false
    use Ecspanse

    def setup(data) do
      data
      |> add_startup_system(TestSystem9)
      |> add_system(TestSystem10, run_in_state: [:foo])
      |> add_system(TestSystem11, run_in_state: [:bar])
    end
  end

  ##########

  defmodule TestResource2 do
    @moduledoc false
    use Ecspanse.Resource, state: [:foo]
  end

  defmodule TestServer6 do
    @moduledoc false
    use Ecspanse

    def setup(data) do
      data
      |> insert_resource({TestResource2, foo: :bar})
    end
  end

  ###############

  describe "setup/1 callback" do
    test "schedules systems in the correct order" do
      start_supervised({TestServer1, :test})
      Ecspanse.Server.test_server(self())
      state = Ecspanse.Server.debug()

      assert [
               %Ecspanse.System{
                 queue: :startup_systems,
                 module: Ecspanse.System.CreateStartupResources
               },
               %Ecspanse.System{queue: :startup_systems, module: TestSystem1}
             ] = state.startup_systems

      assert [
               %Ecspanse.System{
                 queue: :frame_start_systems,
                 module: TestSystem2
               }
             ] = state.frame_start_systems

      assert [
               %Ecspanse.System{
                 queue: :frame_end_systems,
                 module: TestSystem3
               }
             ] = state.frame_end_systems

      assert [
               %Ecspanse.System{
                 queue: :shutdown_systems,
                 module: TestSystem4
               }
             ] = state.shutdown_systems

      assert [
               [
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: TestSystem5
                 }
               ]
             ] = state.batch_systems
    end

    test "groups batched systems by their locked components" do
      start_supervised({TestServer2, :test})
      Ecspanse.Server.test_server(self())

      state = Ecspanse.Server.debug()

      assert [
               [
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: TestSystem6
                 },
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: TestSystem8
                 }
               ],
               [
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: TestSystem7
                 }
               ]
             ] = state.batch_systems
    end

    test "systems can be grouped in sets" do
      start_supervised({TestServer3, :test})
      Ecspanse.Server.test_server(self())
      state = Ecspanse.Server.debug()

      assert [
               [
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: TestSystem1
                 },
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: TestSystem2
                 }
               ]
             ] = state.batch_systems
    end

    test "async systems order of execution can be customized with the `run_after` option" do
      start_supervised({TestServer4, :test})
      Ecspanse.Server.test_server(self())
      state = Ecspanse.Server.debug()

      assert [
               [
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: TestSystem6
                 }
               ],
               [
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: TestSystem8
                 },
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: TestSystem7
                 }
               ]
             ] = state.batch_systems
    end

    test "systems can run conditionally depending on the data state resource" do
      start_supervised({TestServer5, :test})
      Ecspanse.Server.test_server(self())

      Ecspanse.System.debug()
      :timer.sleep(10)

      assert_receive {:next_frame, _state}

      {:ok, pid_resource} = Ecspanse.Query.fetch_resource(TestResource1)
      Ecspanse.Command.update_resource!(pid_resource, pid: self())
      :timer.sleep(10)

      {:ok, state_resource} = Ecspanse.Query.fetch_resource(Ecspanse.Resource.State)
      refute state_resource.value

      assert_receive {:next_frame, _state}
      refute_receive :foo
      refute_receive :bar
      assert_receive {:next_frame, _state}

      {:ok, state_resource} = Ecspanse.Query.fetch_resource(Ecspanse.Resource.State)
      Ecspanse.Command.update_resource!(state_resource, value: :foo)

      :timer.sleep(10)
      assert_receive {:next_frame, _state}
      {:ok, state_resource} = Ecspanse.Query.fetch_resource(Ecspanse.Resource.State)
      assert state_resource.value == :foo

      :timer.sleep(10)
      assert_receive :foo
      refute_receive :bar
      assert_receive {:next_frame, _state}

      :timer.sleep(10)
      {:ok, state_resource} = Ecspanse.Query.fetch_resource(Ecspanse.Resource.State)
      Ecspanse.Command.update_resource!(state_resource, value: :bar)

      assert_receive {:next_frame, _state}
      {:ok, state_resource} = Ecspanse.Query.fetch_resource(Ecspanse.Resource.State)
      assert state_resource.value == :bar

      :timer.sleep(10)
      assert_receive :bar
      assert_receive {:next_frame, _state}
    end

    test "resources can be inserted on startup" do
      start_supervised({TestServer6, :test})
      Ecspanse.Server.test_server(self())

      assert_receive {:next_frame, _state}
      {:ok, resource} = Ecspanse.Query.fetch_resource(TestResource2)
      assert resource.foo == :bar
    end
  end

  describe "fetch_pid/1" do
    test "fetches the data process" do
      start_supervised({TestServer0, :test})

      assert {:ok, pid} = Ecspanse.fetch_pid()
      assert Process.alive?(pid)
    end
  end

  describe "event/3" do
    test "queues an event for the next frame" do
      start_supervised({TestServer0, :test})
      Ecspanse.Server.test_server(self())

      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, state}
      assert state.frame_data.event_batches == []
      Ecspanse.event(TetsEvent1)
      assert_receive {:next_frame, state}
      assert [[%EcspanseTest.TetsEvent1{}]] = state.frame_data.event_batches
    end

    test "groups in individual batches an event without a batch key, queued multiple times in the same frame" do
      start_supervised({TestServer0, :test})
      Ecspanse.Server.test_server(self())

      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, state}
      assert state.frame_data.event_batches == []
      Ecspanse.event(TetsEvent1)
      Ecspanse.event(TetsEvent1)
      assert_receive {:next_frame, state}

      assert [[%EcspanseTest.TetsEvent1{}], [%EcspanseTest.TetsEvent1{}]] =
               state.frame_data.event_batches
    end

    test "providing unique batch keys, groups the events in the same batch for parallel processing" do
      start_supervised({TestServer0, :test})
      Ecspanse.Server.test_server(self())

      entity_1 = Ecspanse.Util.build_entity(UUID.uuid4())
      entity_2 = Ecspanse.Util.build_entity(UUID.uuid4())

      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, state}
      assert state.frame_data.event_batches == []

      Ecspanse.event(TetsEvent1, batch_key: entity_1.id)
      Ecspanse.event(TetsEvent1, batch_key: entity_2.id)
      Ecspanse.event(TetsEvent1, batch_key: entity_1.id)
      assert_receive {:next_frame, state}

      assert [
               [%EcspanseTest.TetsEvent1{}, %EcspanseTest.TetsEvent1{}],
               [%EcspanseTest.TetsEvent1{}]
             ] = state.frame_data.event_batches
    end

    test "events with the same key are grouped in separate batches" do
      start_supervised({TestServer0, :test})
      Ecspanse.Server.test_server(self())

      batch_key = UUID.uuid4()

      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, _state}
      assert_receive {:next_frame, state}
      assert state.frame_data.event_batches == []

      Ecspanse.event(TetsEvent1, batch_key: batch_key)
      Ecspanse.event(TetsEvent1, batch_key: batch_key)
      Ecspanse.event(TetsEvent2, batch_key: batch_key)
      :timer.sleep(100)

      assert_receive {:next_frame, state}

      assert [
               [%EcspanseTest.TetsEvent1{}],
               [%EcspanseTest.TetsEvent1{}],
               [%EcspanseTest.TetsEvent2{}]
             ] = state.frame_data.event_batches
    end
  end
end
