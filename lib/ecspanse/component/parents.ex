defmodule Ecspanse.Component.Parents do
  @moduledoc """
  A special component provided by the framework to store the Entity's Parents.
  Should use deticated functions and options to modify this component.

  An empty Parents component is automatically added when creating entities, event if no parents are defined at cration time.
  """
  use Ecspanse.Component,
    state: [entities: []]

  @type t :: %__MODULE__{
          entities: list(Ecspanse.Entity.t())
        }
end
