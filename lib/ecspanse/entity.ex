defmodule Ecspanse.Entity do
  @moduledoc """

  Entities are simply identifiers. An entity exists only if it holds at least one component.
  The entities per se are not persisted.

  Entities are represented as a struct with `id` as the only field.

  ## Example
    ```elixir
    %Ecspanse.Entity{id: "cfa1ad89-44b6-4d1f-8590-186354be9158"}
    ```
  """

  alias __MODULE__

  @typedoc "The entity struct."
  @type t :: %Entity{
          id: id()
        }

  @type id :: binary()

  @typedoc """
  An entity_spec is the definition needed to create an entity.
  ### Options
  - `id:` A custom unique id for the entity - binary()
  - `components:` A list of component_spec to be added to the entity
  - `children:` A list of `Entity.t()` to be added as children to the entity. Children entities must already exist.
  - `parents:` A list of `Entity.t()` to be added as parents to the entity. Parent entities must already exist.

  At least one of `components:`, `children:` or `parents:` must be provided, otherwise the entity cannot be persisted.
  """
  @type entity_spec :: {Entity, opts :: keyword()}

  @enforce_keys [:id]
  defstruct [:id]

  @spec fetch(Ecspanse.Entity.id()) :: {:ok, t()} | {:error, :not_found}
  defdelegate fetch(id), to: Ecspanse.Query, as: :fetch_entity
end
