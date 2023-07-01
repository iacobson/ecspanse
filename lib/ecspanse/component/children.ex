defmodule Ecspanse.Component.Children do
  @moduledoc """
  A special component provided by the framework to store the Entity's Children.
  Should use deticated functions and options to modify this component.

  An empty Children component is automatically added when creating entities, even if no childrens are defined at cration time.
  """
  use Ecspanse.Component,
    state: [entities: []]

  @type t :: %__MODULE__{
          entities: list(Ecspanse.Entity.t())
        }
end
