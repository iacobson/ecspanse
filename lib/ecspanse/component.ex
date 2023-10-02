defmodule Ecspanse.Component do
  @moduledoc """
  The `Ecspanse.Component` is the basic building block of the ECS architecture, holding the entity state.
  The components are defined by invoking `use Ecspanse.Component` in their module definition.

  An entity cannot exist without at least a component.
  And the other way around, a component cannot exitst without being allocated to an entity.
  The components hold their own state, and can also be tagged for easy grouping.

  There are two ways of providing the components with their initial state and tags:

  1. At compile time, when invoking the `use Ecspanse.Component`, by providing the `:state` and `:tags` options.
    ```elixir
    defmodule Demo.Components.Position do
      use Ecspanse.Component, state: [x: 3, y: 5], tags: [:map]
    end
    ```

  2. At runtime when creating the components from specs: `t:Ecspanse.Component.component_spec()`:
    ```elixir
    Ecspanse.Command.spawn_entity!({Ecspanse.Entity,
      components: [
        Hero,
        {Demo.Components.Position, [x: 7, y: 2], [:map]},
      ]
    )

    # or

    Ecspanse.Command.add_component!(hero_entity, {Demo.Components.Position, [x: 7, y: 2], [:map]})
    ```

  After their creation, the components become structs with the fields defined in the `state` option of the spec, plus some metadata added by the framework. Components can also be used
  as an Entity lable, without state.

  After being created, components become structs with the provided fields, along with some metadata added by the framework.
  Components can also be used as an entity label, without state.

  There are some special components that are created automatically by the framework:
  - `Ecspanse.Component.Children` - holds the list of child entities.
  - `Ecspanse.Component.Parents` - holds the parent entities.

  ## Options

  - `:state` - a list with all the component state struct keys and their initial values (if any).
  For example: `[:amount, max_amount: 100]`
  - `:tags` - list of atoms that act as tags for the current component. Defaults to [].

  > #### Tags  {: .info}
  > Tags can be added at compile time, and at runtime **only** when creating a new component.
  > They cannot be eddited or removed later on for the existing component.
  >
  > The List of tags added at compile time is merged with the one provided at run time.
  """

  @typedoc """
  A `component_spec` is the definition required to create a component.

  ## Examples

    ```elixir
    Demo.Components.Gold
    {Demo.Components.Gold, [amount: 5]}
    {Demo.Components.Gold, [amount: 5], [:resource, :available]}
    {Demo.Components.Gold, [], [:resource, :available]}
    ```
  """
  @type component_spec ::
          (component_module :: module())
          | {component_module :: module(), initial_state :: keyword()}
          | {component_module :: module(), initial_state :: keyword(), tags :: list(atom())}

  @doc """
  **Optional** callback to validate the component state.
  It takes the component state struct as the only argument and returns `:ok` or an error tuple.

  > #### Info  {: .error}
  > When an error tuple is returned, it raises an exception with the provided error message.

  > #### Note  {: .info}
  > For more complex validations, Ecto schemaless changesets may be useful.
  > - [docs](https://hexdocs.pm/ecto/Ecto.Changeset.html#module-schemaless-changesets)
  > - [article](https://medium.com/very-big-things/towards-maintainable-elixir-the-core-and-the-interface-c267f0da43)

  ## Examples

    ```elixir
    defmodule Demo.Components.Gold do
      use Ecspanse.Component, state: [amount: 0]

      def validate(%__MODULE__{amount: amount}) do
        if amount >= 0 do
          :ok
        else
          {:error, "Gold amount cannot be negative"}
        end
      end
    end
    ```
  """
  @callback validate(component :: struct()) :: :ok | {:error, any()}

  @doc """
  Fetches the component for an entity. It has the same functionality as `Ecspanse.Query.fetch_component/2`,
  but it may be more convenient to use in some cases.

  > #### Implemented Callback  {: .tip}
  > This callback is implemented by the library and can be used as such.

  ## Examples:

    ``` elixir
      {:ok, %Demo.Components.Position{} = position_comopnent} = Demo.Components.Position.fetch(hero_entity)

      # it's the same as:

      {:ok, %Demo.Components.Position{} = position_comopnent} = Ecspanse.Query.fetch_component(hero_entity, Demo.Components.Position)
    ```
  """
  @doc group: :implemented
  @callback fetch(entity :: Ecspanse.Entity.t()) ::
              {:ok, component :: struct()} | {:error, :not_found}

  @doc """
  Lists all components of the current type for all entities.

  > #### Implemented Callback  {: .info}
  > This callback is implemented by the library and can be used as such.

  ## Examples:

    ```elixir
    enemy_components = Demo.Components.Enemy.list()
    ```
  """
  @doc group: :implemented
  @callback list() :: list(component :: struct())

  @optional_callbacks validate: 1

  @doc """
  Utility function. Returns all the components and their state, together with their entity association and tags.

  > #### This function is intended for use only in testing and development environments.  {: .warning}
  """
  @spec debug() ::
          list({
            {Ecspanse.Entity.id(), component_module :: module()},
            tags :: list(atom()),
            component_state :: struct()
          })
  def debug do
    :ets.match_object(Ecspanse.Util.components_state_ets_table(), {:"$0", :"$1", :"$2"})
  end

  defmodule Meta do
    @moduledoc false
    # should not be present in the docs

    @opaque t :: %__MODULE__{
              entity: Ecspanse.Entity.t(),
              module: module(),
              tags: MapSet.t(atom())
            }

    @enforce_keys [:entity, :module]
    defstruct entity: nil, module: nil, tags: []
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      @behaviour Ecspanse.Component

      tags = Keyword.get(opts, :tags, [])

      unless is_list(tags) && Enum.all?(tags, &is_atom/1) do
        raise ArgumentError,
              "Invalid tags for Component: #{inspect(__MODULE__)}. The `:tags` option must be a list of atoms."
      end

      Module.register_attribute(__MODULE__, :ecs_type, accumulate: false)
      Module.register_attribute(__MODULE__, :tags, accumulate: false)
      Module.put_attribute(__MODULE__, :ecs_type, :component)
      Module.put_attribute(__MODULE__, :tags, tags)

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
      def __component_tags__ do
        @tags
      end

      @impl Ecspanse.Component
      def fetch(entity) do
        Ecspanse.Query.fetch_component(entity, __MODULE__)
      end

      @impl Ecspanse.Component
      def list do
        Ecspanse.Query.select({__MODULE__})
        |> Ecspanse.Query.stream()
        |> Stream.map(fn {component} -> component end)
        |> Enum.to_list()
      end
    end
  end
end
