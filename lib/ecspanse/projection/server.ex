defmodule Ecspanse.Projection.Server do
  @moduledoc false
  # The projection server.

  use GenServer

  alias Ecspanse.Projection

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
    projection = run_projection(projection_module, attrs, nil)

    # call the `on_change/3` callback upon initialization to handle the initial projection
    if function_exported?(projection_module, :on_change, 3) do
      apply(projection_module, :on_change, [
        attrs,
        projection,
        %Projection{state: :loading, result: nil}
      ])
    end

    {:ok, %{attrs: attrs, projection: projection, projection_module: projection_module}}
  end

  @impl true
  def handle_call(:update, _from, state) do
    new_projection = run_projection(state.projection_module, state.attrs, state.projection.result)

    with true <- function_exported?(state.projection_module, :on_change, 3),
         false <- new_projection == state.projection do
      apply(state.projection_module, :on_change, [state.attrs, new_projection, state.projection])
    end

    {:reply, :ok, %{state | projection: new_projection}}
  end

  def handle_call(:get, _from, state) do
    {:reply, state.projection, state}
  end

  defp run_projection(projection_module, attrs, current_projection_result) do
    case projection_module.project(attrs) do
      :loading ->
        %Projection{
          state: :loading,
          result: nil,
          loading?: true,
          ok?: false,
          error?: false,
          halted?: false
        }

      {:loading, result} ->
        %Projection{
          state: :loading,
          result: result,
          loading?: true,
          ok?: false,
          error?: false,
          halted?: false
        }

      {:ok, result} ->
        validate_projection(result, projection_module)

        %Projection{
          state: :ok,
          result: result,
          loading?: false,
          ok?: true,
          error?: false,
          halted?: false
        }

      :error ->
        %Projection{
          state: :error,
          result: nil,
          loading?: false,
          ok?: false,
          error?: true,
          halted?: false
        }

      {:error, result} ->
        %Projection{
          state: :error,
          result: result,
          loading?: false,
          ok?: false,
          error?: true,
          halted?: false
        }

      :halt ->
        %Projection{
          state: :halt,
          result: current_projection_result,
          loading?: false,
          ok?: false,
          error?: false,
          halted?: true
        }

      _else ->
        raise ArgumentError,
              "The #{Kernel.inspect(projection_module)} `projection/1` callback must return one of `:loading`, `{:loading, any()}`, `:ok`, `{:ok, struct()}`, `:error`, `{:error, any()}` or `:wait`."
    end
  end

  defp validate_projection(projection, projection_module) do
    unless is_struct(projection) and projection.__struct__ == projection_module do
      raise ArgumentError,
            "Invalid projection result for Projection: #{Kernel.inspect(projection_module)}. The success result must be a #{Kernel.inspect(projection_module)} struct."
    end
  end
end
