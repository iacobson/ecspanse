defmodule Ecspanse do
  @moduledoc """
  Documentation for `Ecspanse`.

  Add config
  :my_otp_app_name, :ecspanse_secret, "my_strong_secret - optional, only if you need a signed token

  """

  @type data :: %{
          id: binary(),
          world_name: atom() | {:global, term()} | {:via, module(), term()},
          registry_name: atom()
        }

  @doc """
  Creates a new world.


  Opts
  - name: custom world name. Must be unique. Useful when providing also the supervisor name. Can be a {:via, _, _} tuple.
  - startup_events: a list of event_spec that will run only on world startup. Good to setup resources with dynamic data.
  - dyn_sup: name or pid of an existing DynamicSupervisor. If provided, the world will be started as a child of the DynamicSupervisor.
              If not provided, a new DynamicSupervisor will be started.
  - dyn_sup_impl: defaults to 'DynamicSupervisor'. But can be a custome implementation of the DynamicSupervisor functions. Eg: `Horde.DynamicSupervisor`
  """
  @spec new(world_module :: module(), opts :: keyword()) ::
          {:ok, world_token :: binary()} | {:error, any()}
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

    custom_world_name = Keyword.get(opts, :name)

    id = UUID.uuid4()
    world_name = custom_world_name || String.to_atom("world:#{id}")

    events = Keyword.get(opts, :startup_events, []) |> Enum.map(&prepare_event/1)

    data = %{
      id: id,
      world_name: world_name,
      world_module: world_module,
      supervisor: supervisor,
      events: events
    }

    with {:ok, _world_pid} <- supervisor_impl.start_child(supervisor, {Ecspanse.World, data}),
         {:ok, token} <- fetch_token(world_name) do
      {:ok, token}
    else
      {:error, :not_ready} ->
        retry_fetch_token(world_name)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp retry_fetch_token(world_name) do
    case fetch_token(world_name) do
      {:ok, token} ->
        {:ok, token}

      {:error, :not_ready} ->
        retry_fetch_token(world_name)
    end
  end

  @doc """
  TODO
  """
  @spec terminate(token :: binary()) :: :ok
  def terminate(token) do
    %{world_name: world_name} = Ecspanse.Util.decode_token(token)
    GenServer.cast(world_name, :shutdown)
  end

  @doc """
  TODO
  """
  @spec fetch_token(Ecspanse.World.name()) :: {:ok, binary()} | {:error, :not_ready}
  def fetch_token(world_name) do
    case GenServer.call(world_name, :fetch_token) do
      {:ok, token} ->
        {:ok, token}

      {:error, :not_ready} ->
        {:error, :not_ready}
    end
  end

  @spec fetch_world_data(token :: binary()) ::
          {:ok, %{world_name: Ecspanse.World.name(), world_pid: pid()}}
  def fetch_world_data(token) do
    %{world_name: world_name, world_pid: world_pid} = Ecspanse.Util.decode_token(token)
    {:ok, %{world_name: world_name, world_pid: world_pid}}
  end

  @doc """
  Adds an event to the world.
  TODO
  """
  @spec event(Ecspanse.Event.event_spec(), token :: binary()) :: :ok
  def event(event_spec, token) do
    event = prepare_event(event_spec)

    %{events_ets_name: events_ets_name} = Ecspanse.Util.decode_token(token)
    :ets.insert(events_ets_name, event)
  end

  defp prepare_event(event_spec) do
    {event_module, key, event_payload} =
      case event_spec do
        {event_module, key, event_payload}
        when is_atom(event_module) and is_list(event_payload) ->
          validate_event(event_module)
          {event_module, key, event_payload}

        {event_module, key} when is_atom(event_module) ->
          validate_event(event_module)
          {event_module, key, []}
      end

    event_payload = event_payload |> Keyword.put(:inserted_at, System.os_time())
    {{event_module, key}, struct!(event_module, event_payload)}
  end

  defp validate_event(event_module) do
    unless event_module.__ecs_type__() == :event do
      raise ArgumentError, "The module #{inspect(event_module)} must be an event."
    end
  end
end
