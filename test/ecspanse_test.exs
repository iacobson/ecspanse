defmodule EcspanseTest do
  use ExUnit.Case

  defmodule TestWorld do
    @moduledoc false
    use Ecspanse.World

    @impl true
    def setup(world) do
      world
    end
  end

  defmodule TestStartupEvent do
    @moduledoc false
    use Ecspanse.Event, fields: [:data]
  end

  defmodulle TestStartupSystem do
    @moduledoc false
    use Ecspanse.System

    @impl true
    def run(frame) do
      Enum.each(frame.event_batches, fn events ->
        Enum.each(events, fn event ->
          do_run(event)
        end)
      end)
    end

    defp do_run(event) do
      case event do
        %TestStartupEvent{data: data} ->
          send(self(), {:startup, data})

        _ ->
          nil
      end
    end
  end

  describe "new/2" do
    test "creates a new world" do
      assert {:ok, _token} = Ecspanse.new(TestWorld)
      assert {:ok, token} = Ecspanse.new(TestWorld, name: TestName)

      token_payload = Ecspanse.Util.decode_token(token)
      assert token_payload.world_name == TestName
    end
  end
end
