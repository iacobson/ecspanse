defmodule Ecspanse.StateTest do
  use ExUnit.Case

  defmodule ParentProcess do
    @moduledoc false
    use Ecspanse.Resource, state: [:pid]
  end

  defmodule TestState do
    @moduledoc false
    use Ecspanse.State, states: [:foo, :bar, :baz], default: :foo
  end

  defmodule TestSystem do
    @moduledoc false
    alias Ecspanse.Event.StateTransition

    use Ecspanse.System,
      event_subscriptions: [Ecspanse.Event.StateTransition]

    @impl true
    def run(
          %StateTransition{
            module: TestState,
            previous_state: previous_state,
            current_state: current_state
          },
          _frame
        ) do
      {:ok, %ParentProcess{pid: pid}} = Ecspanse.Query.fetch_resource(ParentProcess)

      send(pid, %{
        module: TestState,
        previous_state: previous_state,
        current_state: current_state
      })
    end
  end

  defmodule TestServer do
    @moduledoc false
    use Ecspanse

    def setup(data) do
      data
      |> init_state({TestState, :bar})
      |> add_frame_end_system(TestSystem)
    end
  end

  ######

  setup do
    start_supervised({TestServer, :test})
    Ecspanse.Server.test_server(self())
    # simulate commands are run from a System
    Ecspanse.System.debug()

    :ok
  end

  describe "set_state!/1" do
    test "transition state" do
      assert_receive {:next_frame, _state}
      Ecspanse.Command.insert_resource!({ParentProcess, pid: self()})

      assert TestState.get_state!() == :bar
      TestState.set_state!(:baz)
      assert TestState.get_state!() == :baz
      assert_receive {:next_frame, _state}

      assert_receive %{
        module: TestState,
        previous_state: :bar,
        current_state: :baz
      }
    end
  end
end
