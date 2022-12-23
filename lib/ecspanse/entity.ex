defmodule Ecspanse.Entity do
  @moduledoc """

  Entities are just IDs. An entity exists only as a holder of components.
  The entities per se are not persisted.
  """

  alias __MODULE__

  @type t :: %Entity{
          id: id()
        }

  @type id :: binary()

  @typedoc """
  An entity_spec is the definition needed to create an entity.
  ### Options
  - `name:` A custom unique name for the entity - binary()
  - `components:` A list of component_spec to be added to the entity
  - `children:` A list of `Entity.t()` to be added as children to the entity. Children entities must already exist.
  - `parents:` A list of `Entity.t()` to be added as parents to the entity. Parent entities must already exist.
  """
  @type entity_spec :: {Entity, opts :: keyword()}

  @enforce_keys [:id]
  defstruct [:id]

  @doc """
  Returns an Entity struct for a provided ID.
  There is no guarantee that the returned Entity exists (has components)
  """
  @spec build(binary()) :: t()
  def build(id) do
    __MODULE__ |> struct(id: id)
  end
end
