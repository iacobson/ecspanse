defmodule Ecspanse.Resource do
  @moduledoc """
  # TODO
  Resources act like global resources, independent of entities.
  Used for configuration, game state, etc.
  Resources can be created, updated or deleted only from sysnchronous Systems.

  - opts
    - state: must be a list with all the Rerource state struct keys and their initial values (if any)
    Eg: [:foo, :bar, baz: 1]
    - access_mode:  :write | :readonly  - defaults to :write

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
  Utility function used for developement.
  Returns all their resources and their state, toghether with their entity association.
  """
  @spec debug(token :: binary()) :: list(resource_key_value())
  def debug(token) do
    if Mix.env() in [:dev, :test] do
      %{resources_state_ets_name: resources_state_ets_name} = Ecspanse.Util.decode_token(token)

      :ets.match_object(resources_state_ets_name, {:"$0", :"$1"})
    else
      {:error, "debug is only available in dev and test"}
    end
  end

  defmodule Meta do
    @moduledoc false
    # should not be present in the docs

    @opaque t :: %__MODULE__{
              module: module(),
              access_mode: :write | :readonly
            }

    @enforce_keys [:module, :access_mode]
    defstruct module: nil, access_mode: nil
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      @behaviour Ecspanse.Resource
      @allowed_access_mode [:write, :readonly]

      resource_access_mode = Keyword.get(opts, :access_mode, :write)

      if resource_access_mode not in @allowed_access_mode do
        raise ArgumentError,
              "Invalid access mode for Resource: #{inspect(__MODULE__)}. Allowed access modes are: #{inspect(@allowed_access_mode)}"
      end

      Module.register_attribute(__MODULE__, :ecs_type, accumulate: false)
      Module.register_attribute(__MODULE__, :resource_access_mode, accumulate: false)
      Module.put_attribute(__MODULE__, :ecs_type, :resource)
      Module.put_attribute(__MODULE__, :resource_access_mode, resource_access_mode)

      state = Keyword.get(opts, :state, [])

      unless is_list(state) do
        raise ArgumentError,
              "Invalid state for Resource: #{inspect(__MODULE__)}. The `:state` option must be a list with all the Resource state struct keys and their initial values (if any). Eg: [:foo, :bar, baz: 1]"
      end

      state = state |> Keyword.put(:__meta__, nil)

      @derive {Inspect, except: [:__meta__]}
      @enforce_keys [:__meta__]
      defstruct state

      ### Internal functions ###
      # not exposed in the docs

      @doc false
      def __ecs_type__ do
        @ecs_type
      end

      @doc false
      def __resource_access_mode__ do
        @resource_access_mode
      end
    end
  end

  #############################
  #    INTERNAL STATE         #
  #############################

  @opaque resource_key_value ::
            {resource_module :: module(), resource_state :: struct()}
end
