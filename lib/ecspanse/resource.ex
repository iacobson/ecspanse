defmodule Ecspanse.Resource do
  @moduledoc """
  # TODO
  Resources act like global resources, independent of entities.
  Used for configuration, game state, etc.
  Resources can be created, updated or deleted only from sysnchronous Systems.

  - opts
    - state: must be a list with all the Rerource state struct keys and their initial values (if any)
    Eg: [:foo, :bar, baz: 1]

  """

  @type resource_spec ::
          (resource_module :: module())
          | {resource_module :: module(), initial_state :: keyword()}

  @doc """
  Optional callback to validate the resource state.
  Takes a map with the resource state and returns `:ok` or an error tuple.
  In case an error is returned, it raises with the proviced error message.


  Note: For more complex validations, Ecto schemaless changesets can be used
  https://hexdocs.pm/ecto/Ecto.Changeset.html#module-schemaless-changesets
  https://medium.com/very-big-things/towards-maintainable-elixir-the-core-and-the-interface-c267f0da43
  """
  @callback validate(resource :: struct()) :: :ok | {:error, any()}
  @optional_callbacks validate: 1

  @doc """
  TODO
  Utility function used for developement.
  Returns all their resources and their state, toghether with their entity association.

  > #### This function is intended for use only in testing and development environments.  {: .warning}
  """
  @spec debug() :: list(resource_key_value())
  def debug do
    :ets.match_object(Ecspanse.Util.resources_state_ets_table(), {:"$0", :"$1", :"$2"})
  end

  defmodule Meta do
    @moduledoc false
    # should not be present in the docs

    @opaque t :: %__MODULE__{
              module: module()
            }

    @enforce_keys [:module]
    defstruct module: nil
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      @behaviour Ecspanse.Resource

      Module.register_attribute(__MODULE__, :ecs_type, accumulate: false)
      Module.put_attribute(__MODULE__, :ecs_type, :resource)

      state = Keyword.get(opts, :state, [])

      unless is_list(state) do
        raise ArgumentError,
              "Invalid state for Resource: #{inspect(__MODULE__)}. The `:state` option must be a list with all the Resource state struct keys and their initial values (if any). Eg: [:foo, :bar, baz: 1]"
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
    end
  end

  #############################
  #    INTERNAL STATE         #
  #############################

  @opaque resource_key_value ::
            {resource_module :: module(), resource_state :: struct()}
end
