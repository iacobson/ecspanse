defmodule Ecspanse.Component.Name do
  @moduledoc """
  A basic name component implemented by the library.
  While this component can be used by the game logic, it serves also for debugging purposes
  and as a way for third-party libraries to identify entities.
  """
  use Ecspanse.Component,
    state: [:name]

  @type t :: %__MODULE__{
          name: String.t()
        }

  @impl true
  def validate(%__MODULE__{name: name}) do
    if is_binary(name) and String.valid?(name) do
      :ok
    else
      {:error, "The name must be a valid string."}
    end
  end
end
