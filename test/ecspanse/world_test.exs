defmodule Ecspanse.WorldTest do
  use ExUnit.Case

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

  defmodule TestWorld1 do
    @moduledoc false
    use Ecspanse.World

    def setup(world) do
      world
      |> Ecspanse.World.add_system(TestSystem5)
      |> Ecspanse.World.add_frame_end_system(TestSystem3)
      |> Ecspanse.World.add_frame_start_system(TestSystem2)
      |> Ecspanse.World.add_startup_system(TestSystem1)
      |> Ecspanse.World.add_shutdown_system(TestSystem4)
    end
  end

  ##########

  defmodule TestComponent1 do
    @moduledoc false
    use Ecspanse.Component
  end

  defmodule TestSystem6 do
    @moduledoc false
    use Ecspanse.System, lock_components: [Ecspanse.WorldTest.TestComponent1]

    def run(_frame), do: :ok
  end

  defmodule TestSystem7 do
    @moduledoc false
    use Ecspanse.System, lock_components: [Ecspanse.WorldTest.TestComponent1]

    def run(_frame), do: :ok
  end

  defmodule TestSystem8 do
    @moduledoc false
    use Ecspanse.System

    def run(_frame), do: :ok
  end

  defmodule TestWorld2 do
    @moduledoc false
    use Ecspanse.World

    def setup(world) do
      world
      |> Ecspanse.World.add_system(TestSystem6)
      |> Ecspanse.World.add_system(TestSystem7)
      |> Ecspanse.World.add_system(TestSystem8)
    end
  end

  ##########

  defmodule TestWorld3 do
    @moduledoc false
    use Ecspanse.World

    def setup(world) do
      world
      |> Ecspanse.World.add_system_set({__MODULE__, :test_system_set})
    end

    def test_system_set(world) do
      world
      |> Ecspanse.World.add_system(TestSystem1)
      |> Ecspanse.World.add_system(TestSystem2)
    end
  end

  ##########

  defmodule TestWorld4 do
    @moduledoc false
    use Ecspanse.World

    def setup(world) do
      world
      |> Ecspanse.World.add_system(TestSystem6)
      |> Ecspanse.World.add_system(TestSystem8, run_after: [TestSystem6])
      |> Ecspanse.World.add_system(TestSystem7)
    end
  end

  ##########

  defmodule TestEvent1 do
    @moduledoc false
    use Ecspanse.Event, fields: [:pid]
  end

  defmodule TestResource1 do
    @moduledoc false
    use Ecspanse.Resource, state: [pid: nil]
  end

  defmodule TestSystem9 do
    @moduledoc false
    use Ecspanse.System,
      events_subscription: [TestEvent1]

    def run(%TestEvent1{} = event, _frame) do
      Ecspanse.Command.insert_resource!({TestResource1, pid: event.pid})
    end
  end

  defmodule TestSystem10 do
    @moduledoc false
    use Ecspanse.System

    def run(frame) do
      {:ok, resource} = Ecspanse.Query.fetch_resource(TestResource1, frame.token)
      send(resource.pid, :foo)
    end
  end

  defmodule TestSystem11 do
    @moduledoc false
    use Ecspanse.System

    def run(frame) do
      {:ok, resource} = Ecspanse.Query.fetch_resource(TestResource1, frame.token)
      send(resource.pid, :bar)
    end
  end

  defmodule TestWorld5 do
    @moduledoc false
    use Ecspanse.World

    def setup(world) do
      world
      |> Ecspanse.World.add_startup_system(TestSystem9)
      |> Ecspanse.World.add_system(TestSystem10, run_in_state: [:foo])
      |> Ecspanse.World.add_system(TestSystem11, run_in_state: [:bar])
    end
  end

  ##########

  describe "setup/1 callback" do
    test "schedules systems in the correct order" do
      assert {:ok, token} = Ecspanse.new(TestWorld1, name: TestName1, test: true)
      state = Ecspanse.World.debug(token)

      assert [
               %Ecspanse.System{
                 queue: :startup_systems,
                 module: Ecspanse.System.CreateDefaultResources
               },
               %Ecspanse.System{queue: :startup_systems, module: Ecspanse.WorldTest.TestSystem1}
             ] = state.startup_systems

      assert [
               %Ecspanse.System{
                 queue: :frame_start_systems,
                 module: Ecspanse.WorldTest.TestSystem2
               }
             ] = state.frame_start_systems

      assert [
               %Ecspanse.System{
                 queue: :frame_end_systems,
                 module: Ecspanse.WorldTest.TestSystem3
               }
             ] = state.frame_end_systems

      assert [
               %Ecspanse.System{
                 queue: :shutdown_systems,
                 module: Ecspanse.WorldTest.TestSystem4
               }
             ] = state.shutdown_systems

      assert [
               [
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: Ecspanse.WorldTest.TestSystem5
                 }
               ]
             ] = state.batch_systems
    end

    test "groups batched systems by their locked components" do
      assert {:ok, token} = Ecspanse.new(TestWorld2, name: TestName2, test: true)
      state = Ecspanse.World.debug(token)

      assert [
               [
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: Ecspanse.WorldTest.TestSystem6
                 },
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: Ecspanse.WorldTest.TestSystem8
                 }
               ],
               [
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: Ecspanse.WorldTest.TestSystem7
                 }
               ]
             ] = state.batch_systems
    end

    test "systems can be grouped in sets" do
      assert {:ok, token} = Ecspanse.new(TestWorld3, name: TestName3, test: true)
      state = Ecspanse.World.debug(token)

      assert [
               [
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: Ecspanse.WorldTest.TestSystem1
                 },
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: Ecspanse.WorldTest.TestSystem2
                 }
               ]
             ] = state.batch_systems
    end

    test "async systems order of execution can be customized with the `run_after` option" do
      assert {:ok, token} = Ecspanse.new(TestWorld4, name: TestName4, test: true)
      state = Ecspanse.World.debug(token)

      assert [
               [
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: Ecspanse.WorldTest.TestSystem6
                 }
               ],
               [
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: Ecspanse.WorldTest.TestSystem8
                 },
                 %Ecspanse.System{
                   queue: :batch_systems,
                   module: Ecspanse.WorldTest.TestSystem7
                 }
               ]
             ] = state.batch_systems
    end

    test "systems can run conditionally depending on the world state resource" do
      assert {:ok, token} =
               Ecspanse.new(TestWorld5,
                 startup_events: [{TestEvent1, pid: self()}],
                 name: TestName5,
                 test: true
               )

      Ecspanse.System.debug(token)

      {:ok, state_resource} = Ecspanse.Query.fetch_resource(Ecspanse.Resource.State, token)
      refute state_resource.value

      assert_receive {:next_frame, _state}
      refute_receive :foo
      refute_receive :bar
      assert_receive {:next_frame, _state}

      {:ok, state_resource} = Ecspanse.Query.fetch_resource(Ecspanse.Resource.State, token)
      Ecspanse.Command.update_resource!(state_resource, value: :foo)

      assert_receive {:next_frame, _state}
      {:ok, state_resource} = Ecspanse.Query.fetch_resource(Ecspanse.Resource.State, token)
      assert state_resource.value == :foo
      assert_receive :foo
      refute_receive :bar
      assert_receive {:next_frame, _state}

      {:ok, state_resource} = Ecspanse.Query.fetch_resource(Ecspanse.Resource.State, token)
      Ecspanse.Command.update_resource!(state_resource, value: :bar)

      assert_receive {:next_frame, _state}
      {:ok, state_resource} = Ecspanse.Query.fetch_resource(Ecspanse.Resource.State, token)
      assert state_resource.value == :bar
      assert_receive :bar
      assert_receive {:next_frame, _state}
    end
  end
end
