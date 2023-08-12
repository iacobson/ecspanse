defmodule Ecspanse.Component.Children do
  @moduledoc """
  The `Children` component is a special component provided by the framework
  to maintain references to an entity's child entities.

  Dedicated queries and commands are provided to interact with this component.

  An empty `Children` component is automatically added upon entity creation,
  even if no child entities are defined at the time of creation.

  > #### Ecspanse parent-child relationships are **bidirectional associations** {: .info}
  """
  use Ecspanse.Component,
    state: [entities: []]

  @typedoc """
  Entity's children list.
  """
  @type t :: %__MODULE__{
          entities: list(Ecspanse.Entity.t())
        }
end
