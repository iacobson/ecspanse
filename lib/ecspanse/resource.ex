defmodule Ecspanse.Resource do
  @moduledoc """
  Resources are global components that don't belong to any entity.

  They are best used for configuration, global state, statistics, etc.

  Resources are defined by invoking `use Ecspanse.Resource` in their module definition.

  ## Options
  - `:state` - a list with all the resource state struct keys and their initial values (if any).
  For example: `[:player_count, max_players: 100]`

  There are two ways of providing the resources with their initial state:

  1. At compile time, when invoking the `use Ecspanse.Resource`, by providing the `:state` option.
    ```elixir
    defmodule Demo.Resources.PlayerCount do
      use Ecspanse.Resource, state: [player_count: 0, max_players: 100]
    end
    ```

  2. At runtime when creating the resources from specs: `t:Ecspanse.Resource.resource_spec()`
    ```elixir
    Ecspanse.Command.insert_resource!({Demo.Resources.Lobby, [max_players: 50]})
    ```

  There are some special resources that are created automatically by the framework:
  - `Ecspanse.Resource.FPS` - tracks the frames per second.
  - `Ecspanse.Resource.State` - a high level state implementation.

  > #### Note  {: .info}
  > Resources can be created, updated or deleted only from synchronous systems.

  """

  @typedoc """
  A `resource_spec` is the definition required to create a resource.

  ## Examples
    ```elixir
    Demo.Resources.Lobby
    {Demo.Resources.Lobby, [max_players: 50]}
    ```
  """
  @type resource_spec ::
          (resource_module :: module())
          | {resource_module :: module(), initial_state :: keyword()}

  @doc """
  **Optional** callback to validate the resource state.

  See `c:Ecspanse.Component.validate/1` for more details.
  """
  @callback validate(resource :: struct()) :: :ok | {:error, any()}
  @optional_callbacks validate: 1

  @doc """
  Utility function. Returns all the resources and their state.

  > #### This function is intended for use only in testing and development environments.  {: .warning}
  """
  @spec debug() :: list({resource_module :: module(), resource_state :: struct()})
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
              "Invalid state for Resource: #{Kernel.inspect(__MODULE__)}. The `:state` option must be a list with all the Resource state struct keys and their initial values (if any). Eg: [:foo, :bar, baz: 1]"
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
end
