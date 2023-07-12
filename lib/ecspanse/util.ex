defmodule Ecspanse.Util do
  @moduledoc false
  # utility functions to be used inside the library
  # should not be exposed in the docs

  use Memoize
  require Ex2ms

  @doc false
  def encode_payload(otp_app, payload) do
    secret = Application.get_env(otp_app, :ecspanse_secret, "default")

    Plug.Crypto.sign(secret, "ecspanse", payload)
  end

  @doc false
  defmemo decode_token(token), max_waiter: 100, waiter_sleep_ms: 5 do
    [_, encoded_payload, _] = String.split(token, ".", parts: 3)

    {unverified_payload, _, _} =
      encoded_payload
      |> Base.url_decode64!(padding: false)
      |> :erlang.binary_to_term([:safe])

    %{otp_app: otp_app} = unverified_payload

    secret = Application.get_env(otp_app, :ecspanse_secret, "default")

    {:ok, payload} = Plug.Crypto.verify(secret, "ecspanse", token, max_age: :infinity)

    payload
  end

  @doc false
  # Returns a map with entity_id as key and a list of component modules as value
  # Example %{"entity_id" => [Component1, Component2]}
  defmemo list_entities_components(components_state_ets_name), max_waiter: 100, waiter_sleep_ms: 5 do
    f =
      Ex2ms.fun do
        {{entity_id, component_module, _component_groups}, _component_state} ->
          {entity_id, component_module}
      end

    :ets.select(components_state_ets_name, f)
    |> Enum.group_by(fn {k, _v} -> k end, fn {_k, v} -> v end)
  end

  @doc false
  # Returns a list of tuples with entity_id, component_groups and component_state
  # Example: [{"entity_id", [:group1,:group2], %MyComponent{foo: :bar}}]
  # Cannot be memoized as it returns the componet state, so it will be invalidated every frame multiple times.
  def list_entities_components_groups(components_state_ets_name) do
    f =
      Ex2ms.fun do
        {{entity_id, _component_module, component_groups}, component_state}
        when component_groups != [] ->
          {entity_id, component_groups, component_state}
      end

    :ets.select(components_state_ets_name, f)
  end

  @doc false
  def run_system_in_state(token, run_in_state) do
    {:ok, %Ecspanse.Resource.State{value: state}} =
      Ecspanse.Query.fetch_resource(Ecspanse.Resource.State, token)

    run_in_state == state
  end

  @doc false
  def run_system_not_in_state(token, run_not_in_state) do
    not run_system_in_state(token, run_not_in_state)
  end

  @doc false
  def validate_events(event_modules) do
    Enum.each(event_modules, fn event_module ->
      validate_ecs_type(
        event_module,
        :event,
        ArgumentError,
        "The module #{inspect(event_module)} must be an event."
      )
    end)

    :ok
  end

  @doc false
  def validate_ecs_type(module, type, exception, attributes) do
    # try, because an invalid module would not implement this function
    try do
      if is_atom(module) && Code.ensure_compiled!(module) && module.__ecs_type__() == type do
        :ok
      else
        raise "validation error"
      end
    rescue
      _exception ->
        reraise exception, attributes, __STACKTRACE__
    end
  end
end
