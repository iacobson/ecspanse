defmodule Ecspanse.Component do
  @moduledoc """
  TODO

  - opts
    - state: must be a list with all the Component state struct keys and their initial values (if any)
    Eg: [:foo, :bar, baz: 1]
    - groups: list of groups (atoms) that this component belongs to. Defaults to []

  """

  @type component_spec ::
          (component_module :: module())
          | {component_module :: module(), initial_state :: keyword()}

  @doc """
  Optional callback to validate the component state.
  Takes the component state struct as only argument and returns `:ok` or an error tuple.

  Attention! When an error is returned, it raises with the provided error message.
  Tip! print useful error messages for debugging.


  Note: For more complex validations, Ecto schemaless changesets can be used
  https://hexdocs.pm/ecto/Ecto.Changeset.html#module-schemaless-changesets
  https://medium.com/very-big-things/towards-maintainable-elixir-the-core-and-the-interface-c267f0da43
  """
  @callback validate(component :: struct()) :: :ok | {:error, any()}
  @optional_callbacks validate: 1

  if Mix.env() in [:dev, :test] do
    @doc """
    Utility function used for developement.
    Returns all their components and their state, toghether with their entity association.
    """
    @spec debug() :: list(component_key_value())
    def debug do
      :ets.match_object(Ecspanse.Util.components_state_ets_table(), {:"$0", :"$1"})
    end
  end

  defmodule Meta do
    @moduledoc false
    # should not be present in the docs

    @opaque t :: %__MODULE__{
              entity: Ecspanse.Entity.t(),
              module: module(),
              groups: list(atom())
            }

    @enforce_keys [:entity, :module]
    defstruct entity: nil, module: nil, groups: []
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      @behaviour Ecspanse.Component

      groups = Keyword.get(opts, :groups, [])

      unless is_list(groups) do
        raise ArgumentError,
              "Invalid groups for Component: #{inspect(__MODULE__)}. The `:groups` option must be a list of atoms."
      end

      Module.register_attribute(__MODULE__, :ecs_type, accumulate: false)
      Module.register_attribute(__MODULE__, :groups, accumulate: false)
      Module.put_attribute(__MODULE__, :ecs_type, :component)
      Module.put_attribute(__MODULE__, :groups, groups)

      state = Keyword.get(opts, :state, [])

      unless is_list(state) do
        raise ArgumentError,
              "Invalid state for Component: #{inspect(__MODULE__)}. The `:state` option must be a list with all the Component state struct keys and their initial values (if any). Eg: [:foo, :bar, baz: 1]"
      end

      state = state |> Keyword.put(:__meta__, nil)

      @enforce_keys [:__meta__]
      defstruct state

      ### Internal functions ###
      # not exposed in the docs

      @doc false
      def __ecs_type__ do
        @ecs_type
      end

      @doc false
      def __component_groups__ do
        @groups
      end
    end
  end

  #############################
  #    INTERNAL STATE         #
  #############################

  @opaque component_key_value ::
            {{Ecspanse.Entity.id(), component_module :: module(), groups :: list(atom())},
             component_state :: struct()}
end
