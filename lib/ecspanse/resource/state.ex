defmodule Ecspanse.Resource.State do
  @moduledoc """
  A special resource provided by the framework to store a generic state.
  This is a high level state, with an atom type value.

  It is useful in controlling the systems execution. But its use
  is not mandatory.

  The initial state can be set, for example, in a startup system.
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
