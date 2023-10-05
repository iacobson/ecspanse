defmodule Ecspanse.Projection do
  @moduledoc """
  The `Ecspanse.Projection` behaviour is used to build state projections.
  The projections are defined by invoking `use Ecspanse.Projection` in their module definition.

  Projections are used to build models and query the state of application across multiple
  entities and their components.

  They are designed to be created and used by external clients (such as UI libraries, for example Phoenix LiveView),

  The Projections are GenServers and the client that creates them is responsible for
  storing their `pid` and using it to communicate with them.

  The module invoking `use Ecspanse.Projection` must implement the mandatory
  `c:Ecspanse.Projection.project/1` callback. This is responsible for
  querying the state and building the projection struct.

  > #### Note  {: .warning}
  > The `project/2` callback runs every frame, after executing all systems.
  > Many projections with complex queries can have a negative impact on performance.

  ## Options
  - `:fields` - a list with all the event struct keys and their initial values (if any)
  For example: `[:pos_x, :pos_y, resources_gold: 0, resources_gems: 0]`

  ## Examples

  ### The Projection

    ```elixir
    defmodule Demo.Projections.Hero do
      use Ecspanse.Projection, fields: [:pos_x, :pos_y, :resources_gold, :resources_gems]

      @impl true
      def project(%{entity_id: entity_id} = _attrs) do
        {:ok, entity} = fetch_entity(entity_id)
        {:ok, pos} = Demo.Components.Position.fetch(entity)
        {:ok, gold} = Demo.Components.Gold.fetch(entity)
        {:ok, gems} = Demo.Components.Gems.fetch(entity)

        struct!(__MODULE__, pos_x: pos.x, pos_y: pos.y, resources_gold: gold.amount, resources_gems: gems.amount)
      end

      @impl true
      def on_change(%{client_pid: pid} = _attrs, new_projection, _previous_projection) do
        # when the projection changes, send it to the client
        send(pid, {:projection_updated, new_projection})
      end
    end
    ```
  ### The Client

    ```elixir
    #...
    projection_pid = Demo.Projections.Hero.start!(%{entity_id: entity.id, client_pid: self()})

    projection = Demo.Projections.Hero.get!(projection_pid)

    # ...
    def handle_info({:projection_updated, projection}, state) do
      # received every time the projection changes
      # ...
    end

    # ...
    Demo.Projections.Hero.stop(projection_pid)
    ```
  """

  @doc """
  Starts a new projection server and returns its `pid`.

  It takes a single attrs `map` argument.

  > #### Info  {: .info}
  > The `attrs` map is passed to the `c:Ecspanse.Projection.project/1`
  > and `c:Ecspanse.Projection.on_change/2` callbacks.

  The caller is responsible for storing the returned `pid`.

  > #### Implemented Callback  {: .tip}
  > This callback is implemented by the library and can be used as such.

  ## Examples

    ```elixir
    projection_pid = Demo.Projections.Hero.start!(%{entity_id: entity.id, client_pid: self()})
    ```
  """
  @doc group: :implemented
  @callback start!(attrs :: map()) :: projection_pid :: pid()

  @doc """
  The `project/1` callback is responsible for querying the state and building the projection struct.

  It takes the `attrs` map argument passed to `c:Ecspanse.Projection.start!/1`.
  It must return the projection struct.

  ## Examples

    ```elixir
      @impl true
      def project(%{entity_id: entity_id} = _attrs) do
        {:ok, entity} = fetch_entity(entity_id)
        {:ok, pos} = Demo.Components.Position.fetch(entity)
        {:ok, gold} = Demo.Components.Gold.fetch(entity)
        {:ok, gems} = Demo.Components.Gems.fetch(entity)

        struct!(__MODULE__, pos_x: pos.x, pos_y: pos.y, resources_gold: gold.amount, resources_gems: gems.amount)
      end
    ```
  """
  @callback project(attrs :: map()) :: projection :: struct()

  @doc """
  Stops the projection server by its `pid`.

  > #### Implemented Callback  {: .tip}
  > This callback is implemented by the library and can be used as such.

  ## Examples

    ```elixir
    Demo.Projections.Hero.stop(projection_pid)
    ```
  """
  @doc group: :implemented
  @callback stop(projection_pid :: pid()) :: :ok

  @doc """
  Gets the projection struct by providing the server `pid`.

  > #### Implemented Callback  {: .tip}
  > This callback is implemented by the library and can be used as such.

  ## Examples

    ```elixir
    %Demo.Projection.Hero{} = Demo.Projections.Hero.get!(projection_pid)
    ```
  """
  @doc group: :implemented
  @callback get!(projection_pid :: pid()) :: projection :: struct()

  @doc """
  Optional callback that is executed every time the projection changes.

  It takes the `attrs` map argument passed to `c:Ecspanse.Projection.start!/1`,
  the new projection and the previous projection structs as arguments. The return value is ignored.

  ## Examples

    ```elixir
    @impl true
    def on_change(%{client_pid: pid} = _attrs, new_projection, _previous_projection) do
      send(pid, {:projection_updated, new_projection})
    end
    ```
  """
  @callback on_change(attrs :: map(), new_projection :: struct(), previous_projection :: struct) ::
              any()

  @optional_callbacks on_change: 3

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      import Ecspanse.Query
      @behaviour Ecspanse.Projection

      projection = Keyword.get(opts, :fields, [])

      unless is_list(projection) do
        raise ArgumentError,
              "Invalid Projection: #{inspect(__MODULE__)}. The `:fields` option must be a list with all the projection struct keys and their initial values (if any). Eg: [:foo, :bar, baz: 1]"
      end

      defstruct projection

      ### Callbacks

      @impl Ecspanse.Projection
      def start!(attrs \\ %{}) do
        unless is_map(attrs) do
          raise ArgumentError,
                "Invalid attrs for Projection: #{inspect(__MODULE__)}. The `start!/1` callback takes a map as argument."
        end

        {:ok, pid} =
          DynamicSupervisor.start_child(
            Ecspanse.Projection.Supervisor,
            {Ecspanse.Projection.Server, %{attrs: attrs, projection_module: __MODULE__}}
          )

        pid
      end

      @impl Ecspanse.Projection
      def get!(projection_pid) do
        unless is_pid(projection_pid) do
          raise ArgumentError,
                "Invalid projection_pid for Projection: #{inspect(__MODULE__)}. The `get/1` callback takes a pid as argument."
        end

        GenServer.call(projection_pid, :get)
      end

      @impl Ecspanse.Projection
      def stop(projection_pid) do
        unless is_pid(projection_pid) do
          raise ArgumentError,
                "Invalid projection_pid for Projection: #{inspect(__MODULE__)}. The `stop/1` callback takes a pid as argument."
        end

        DynamicSupervisor.terminate_child(Ecspanse.Projection.Supervisor, projection_pid)
      end
    end
  end
end
