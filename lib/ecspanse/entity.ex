defmodule Ecspanse.Entity do
  @moduledoc """

  Entities are only identifiers. An entity exists only if it holds at least one component.
  The entities per se are not persisted.

  Entities are represented as a struct with `id` as the only field.

  ## Examples
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
  An `entity_spec` is the definition required to create an entity.
  ## Options
  - `:id` - a custom unique ID for the entity (binary). If not provided, a random UUID will be generated.
  - `:components` - a list of `t:Ecspanse.Component.component_spec/0` to be added to the entity.
  - `:children` A list of `t:Ecspanse.Entity.t/0` to be added as children to the entity. Children entities should already exist.
  - `:parents` A list of `t:Ecspanse.Entity.t/0` to be added as parents to the entity. Parent entities should already exist.

  > #### Note  {: .info}
  > At least one of the `:components`, `:children` or `:parents` options must be provided,
  > otherwise the entity cannot be persisted.

  > #### Entity ID  {: .warning}
  > The entity IDs must be unique. Attention when providing the `:id` option as part of the `entity_spec`.
  > If the provided ID is not unique, spawning entities will raise an error.
  """
  @type entity_spec :: {Entity, opts :: keyword()}

  @enforce_keys [:id]
  defstruct [:id]

  @spec fetch(Ecspanse.Entity.id()) :: {:ok, t()} | {:error, :not_found}
  defdelegate fetch(id), to: Ecspanse.Query, as: :fetch_entity
end
