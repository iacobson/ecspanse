defmodule Ecspanse.Template.EventTest do
  use ExUnit.Case

  defmodule TestEventTemplate do
    @moduledoc false
    use Ecspanse.Template.Event, fields: [:foo]
  end

  defmodule TestEvent1 do
    @moduledoc false
    use TestEventTemplate
  end

  defmodule TestEvent2 do
    @moduledoc false
    use TestEventTemplate, fields: [:bar]
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

  test "event template provides default fields for the events using it" do
    assert_receive {:next_frame, _state}
    Ecspanse.event({TestEvent1, [foo: 1]})
    Ecspanse.event({TestEvent2, [foo: 2, bar: 3]})
    assert_receive {:next_frame, state}
    assert [[%TestEvent1{foo: 1}, %TestEvent2{foo: 2, bar: 3}]] = state.frame_data.event_batches
  end
end
