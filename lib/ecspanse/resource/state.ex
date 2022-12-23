defmodule Ecspanse.Resource.State do
  @moduledoc """
  # TODO
  A special resource provided by the framework to store the world state.
  This is a high level state, with an atom type value.
  It is very useful in controlling the Systems execution.

  The initial state can be set in a startup system
  """
  use Ecspanse.Resource,
    state: [value: nil]

  alias __MODULE__

  @type t :: %__MODULE__{
          value: atom()
        }

  def validate(%State{value: value}) do
    if is_atom(value) do
      :ok
    else
      {:error, "Invalid state value: #{inspect(value)}. The Resource.State value must be an atom"}
    end
  end
end
