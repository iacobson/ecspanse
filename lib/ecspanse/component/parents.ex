defmodule Ecspanse.Component.Parents do
  @moduledoc """
  The `Parents` component is a special component provided by the framework
  to maintain references to an entity's parent entities.

  Dedicated queries and commands are provided to interact with this component.

  An empty `Parents` component is automatically added upon entity creation,
  even if no parent entities are defined at the time of creation.

  > #### Ecspanse parent-child relationships are **bidirectional associations** {: .info}
  """
  use Ecspanse.Component,
    state: [entities: []]

  @typedoc """
  Entity's parents list.
  """
  @type t :: %__MODULE__{
          entities: list(Ecspanse.Entity.t())
        }
end
