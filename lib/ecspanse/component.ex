defmodule Ecspanse.Component do
  @moduledoc """
  TODO

  - opts
    - state: must be a list with all the Component state struct keys and their initial values (if any)
    Eg: [:foo, :bar, baz: 1]
    - access_mode:  :write | :readonly | :entity_type - defaults to :write

    `entity_type` access mode is an optimization. Its use is not mandatory.
    But it may greatly improve parallel system execution.
    One entity may have only one component with `entity_type` access mode.
    In the System lock_components option, the component must be specified as `{component, entity_type_component}`
    The entity_type Component does not accept any state. It is used as a simple Entity tag.
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

  @doc """
  Utility function used for developement.
  Returns all their components and their state, toghether with their entity association.
  """
  @spec debug(token :: binary()) :: list(component_key_value())
  def debug(token) do
    if Mix.env() in [:dev, :test] do
      %{components_state_ets_name: components_state_ets_name} = Ecspanse.Util.decode_token(token)

      :ets.match_object(components_state_ets_name, {:"$0", :"$1"})
    else
      {:error, "debug is only available in dev and test"}
    end
  end

  defmodule Meta do
    @moduledoc false
    # should not be present in the docs

    @opaque t :: %__MODULE__{
              entity: Ecspanse.Entity.t(),
              module: module(),
              access_mode: :write | :readonly | :entity_type
            }

    @enforce_keys [:entity, :module, :access_mode]
    defstruct entity: nil, module: nil, access_mode: nil
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      @behaviour Ecspanse.Component
      @allowed_access_mode [:write, :readonly, :entity_type]

      component_access_mode = Keyword.get(opts, :access_mode, :write)

      if component_access_mode not in @allowed_access_mode do
        raise ArgumentError,
              "Invalid access mode for Component: #{inspect(__MODULE__)}. Allowed access modes are: #{inspect(@allowed_access_mode)}"
      end

      if component_access_mode == :entity_type and Keyword.has_key?(opts, :state) do
        raise ArgumentError,
              "Invalid state for Component: #{inspect(__MODULE__)}. Components with entity_type access_mode do not accept state."
      end

      Module.register_attribute(__MODULE__, :ecs_type, accumulate: false)
      Module.register_attribute(__MODULE__, :component_access_mode, accumulate: false)
      Module.put_attribute(__MODULE__, :ecs_type, :component)
      Module.put_attribute(__MODULE__, :component_access_mode, component_access_mode)

      state = Keyword.get(opts, :state, [])

      unless is_list(state) do
        raise ArgumentError,
              "Invalid state for Component: #{inspect(__MODULE__)}. The `:state` option must be a list with all the Component state struct keys and their initial values (if any). Eg: [:foo, :bar, baz: 1]"
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
      def __component_access_mode__ do
        @component_access_mode
      end
    end
  end

  #############################
  #    INTERNAL STATE         #
  #############################

  @opaque component_key_value ::
            {{Ecspanse.Entity.id(), component_module :: module()}, component_state :: struct()}
end
