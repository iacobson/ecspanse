defmodule Ecspanse.Projection.Server do
  @moduledoc false
  # The projection server.

  use GenServer

  def child_spec(payload) do
    %{
      id: UUID.uuid4(),
      start: {__MODULE__, :start_link, [payload]},
      restart: :temporary,
      type: :worker
    }
  end

  def start_link(payload) do
    GenServer.start_link(__MODULE__, payload)
  end

  @impl true
  def init(%{attrs: attrs, projection_module: projection_module}) do
    projection = projection_module.project(attrs)

    validate_projection(projection, projection_module)

    {:ok, %{attrs: attrs, projection: projection, projection_module: projection_module}}
  end

  @impl true
  def handle_call(:update, _from, state) do
    new_projection = state.projection_module.project(state.attrs)

    validate_projection(new_projection, state.projection_module)

    with true <- function_exported?(state.projection_module, :on_change, 2),
         false <- new_projection == state.projection do
      apply(state.projection_module, :on_change, [state.attrs, new_projection])
    end

    {:reply, :ok, %{state | projection: new_projection}}
  end

  def handle_call(:get, _from, state) do
    {:reply, state.projection, state}
  end

  defp validate_projection(projection, projection_module) do
    unless is_struct(projection) and projection.__struct__ == projection_module do
      raise ArgumentError,
            "Invalid projection for Projection: #{inspect(projection_module)}. The `projection/1` callback must return a #{inspect(projection_module)} struct."
    end
  end
end
