defmodule Ecspanse do
  @moduledoc """

  TODO needs small updas

  Ecspanse is an experimental Entity Component System (ECS) library for Elixir, designed to manage game state and provide tools for measuring time and frame duration.
  It is not a game engine, but a flexible foundation for building game logic.

  The core structure of the Ecspanse library is:

  - `Ecspanse.World`: The world orchestrates the execution of systems and the storage of entities, components, and resources.
  Each world schedules system execution and listens for events.
  - `Ecspanse.Entity`: A simple struct with an ID, serving as a holder for components.
  - `Ecspanse.Component`: A struct that holds state information.
  - `Ecspanse.System`: The core logic of the library. Systems are configured for each world and run every frame, either synchronously or asynchronously.
  - `Ecspanse.Resource`: Global state storage, similar to components but not tied to a specific entity. Resources can only be created, updated, and deleted by synchronously executed systems.
  - `Ecspanse.Query`: A tool for retrieving entities, components, or resources.
  - `Ecspanse.Command`: A mechanism for changing component and resource state, which can only be triggered from a system.
  - `Ecspanse.Event`: A mechanism for triggering events, which can be listened to by systems. It is the way to communicate externally with the world.

  """

  alias Ecspanse.Util

  @doc """
  Creates a new world with the specified options.


  ## Options

  - `:name` - A custom, unique world name. Useful when providing a supervisor name. Can be a `{:via, _, _}` tuple.
  - `:startup_events` - A list of event specs that will run only on world startup. Useful for setting up resources with dynamic data.
  They are only available in the startup systems.
  - `:dyn_sup` - The name or PID of an existing DynamicSupervisor. If provided, the world will be started as a child of the DynamicSupervisor.
  If not provided, a new DynamicSupervisor will be started.
  - `:dyn_sup_impl` - Defaults to `DynamicSupervisor`. Can be a custom implementation of the DynamicSupervisor functions, e.g., `Horde.DynamicSupervisor`.
  - `:test` - boolean, defaults to false. If `true`, the world will be started in test mode. A `{:next_frame, %World.State{}}` tupple message will be sent to the process running this function at the beginning of each frame.
  This is useful for tests or debugging

  ## Examples

      iex> Ecspanse.new(MyWorldModule)
      :ok

      iex> Ecspanse.new(MyWorldModule, name: :my_custom_world)
      :ok
  """

  @spec new(world_module :: module(), opts :: keyword()) ::
          :ok | {:error, any()}
  def new(world_module, opts \\ []) do
    supervisor =
      case Keyword.get(opts, :dyn_sup) do
        nil ->
          {:ok, supervisor_pid} = DynamicSupervisor.start_link(strategy: :one_for_one)
          supervisor_pid

        supervisor ->
          supervisor
      end

    supervisor_impl = Keyword.get(opts, :dyn_sup_impl, DynamicSupervisor)

    test = Keyword.get(opts, :test, false)
    test_pid = if test, do: self(), else: nil

    id = UUID.uuid4()
    world_name = Ecspanse.World

    events = Keyword.get(opts, :startup_events, []) |> Enum.map(&prepare_event(&1, "default"))

    data = %{
      id: id,
      world_name: world_name,
      world_module: world_module,
      supervisor: supervisor,
      events: events,
      test: test,
      test_pid: test_pid
    }

    case supervisor_impl.start_child(supervisor, {Ecspanse.World, data}) do
      {:ok, _world_pid} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Retrieves the world process PID.
  If the world process is not found, it returns an error.

  ## Examples

      iex> Ecspanse.fetch_world_process()
      {:ok, %{name: world_name, pid: world_pid}}

  """
  @spec fetch_world_process() ::
          {:ok, pid()} | {:error, :not_found}
  def fetch_world_process do
    case Process.whereis(Ecspanse.World) do
      pid when is_pid(pid) ->
        {:ok, pid}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Queues a world event to be processed in the next frame.

  The first argument is an event spec.

  ## Options

  - `:batch_key` - A key for grouping multiple similar events in different batches within the same frame.
  The world groups the events into batches with unique `{EventModule, batch_key}` combinations.
  In most cases, the key may be an entity ID that either triggers or is impacted by the event.
  Defaults to "default", meaning that similar events will be processed in separate batches.

  ## Examples

      iex> Ecspanse.event(MyEventModule,  batch_key: my_entity.id)
      :ok

  """
  @spec event(
          Ecspanse.Event.event_spec(),
          opts :: keyword()
        ) :: :ok
  def event(event_spec, opts \\ []) do
    batch_key = Keyword.get(opts, :batch_key, "default")

    event = prepare_event(event_spec, batch_key)

    :ets.insert(Util.events_ets_table(), event)
    :ok
  end

  defp prepare_event(event_spec, batch_key) do
    {event_module, key, event_payload} =
      case event_spec do
        {event_module, event_payload}
        when is_atom(event_module) and is_list(event_payload) ->
          validate_event(event_module)
          {event_module, batch_key, event_payload}

        event_module when is_atom(event_module) ->
          validate_event(event_module)
          {event_module, batch_key, []}
      end

    event_payload =
      event_payload
      |> Keyword.put(:inserted_at, System.os_time())

    {{event_module, key}, struct!(event_module, event_payload)}
  end

  defp validate_event(event_module) do
    Ecspanse.Util.validate_ecs_type(
      event_module,
      :event,
      ArgumentError,
      "The module #{inspect(event_module)} must be a Event"
    )
  end
end
