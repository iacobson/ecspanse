defmodule Ecspanse.State do
  @moduledoc """
  TODO

  State transitions may happen only in synchronous systems.

  Explain that the state transition happens sync, in the current system, but it will be picked up
  by run_if and run_in_state conditions only in the next frame. For sensitive systems, a good mitigation
  is to make state transition systems as frame_end, and run them as late in the frame as possible.
  """

  @type state_spec ::
          (state_module :: module())
          | {state_module :: module(), initial_state :: atom()}

  @doc """
  Gets the current state for the state module.

  The module must `use Ecspanse.State`. Otherwise the function will raise an error.

  > #### Implemented Callback  {: .tip}
  > This callback is implemented by the library and can be used as such.

  ## Examples:

    ``` elixir
      current_state_atom = Demo.States.Game.get_state!()
    ```
  """
  @doc group: :implemented
  @callback get_state!() :: atom()

  @doc """
  Sets the current state for the state module.

  This function can run only in a synchronous system, otherwise it will raise an error.
  It is advised against calling this function multiple times in the same system for the same state module.

  Upon state change, a `Ecspanse.Event.StateTransition` event is automatically emitted.

  > #### Implemented Callback  {: .tip}
  > This callback is implemented by the library and can be used as such.

  ## Examples:

    ``` elixir
      Demo.States.Game.set_state!(:paused)
    ```
  """
  @doc group: :implemented
  @callback set_state!(next_state :: atom()) :: :ok

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      @behaviour Ecspanse.State
      states = Keyword.get(opts, :states)

      unless is_list(states) do
        raise ArgumentError,
              "Invalid states list for State: #{Kernel.inspect(__MODULE__)}. The `:states` option must be a list of atoms with all possible states."
      end

      default = Keyword.get(opts, :default)

      unless is_atom(default) and default in states do
        raise ArgumentError,
              "Invalid default state for State: #{Kernel.inspect(__MODULE__)}. The `:default` option must be an atom from `:states` option: #{Kernel.inspect(states)}."
      end

      Module.register_attribute(__MODULE__, :states, accumulate: false)
      Module.put_attribute(__MODULE__, :states, states)

      use Ecspanse.Resource,
        state: [current: default]

      alias __MODULE__

      @type t :: %__MODULE__{
              current: atom()
            }

      @impl Ecspanse.Resource
      def validate(%__MODULE__{current: current}) do
        if is_atom(current) and current in @states do
          :ok
        else
          {:error,
           "Invalid current state for State: #{Kernel.inspect(__MODULE__)}. The current state must be an atom from #{Kernel.inspect(@states)}."}
        end
      end

      @impl Ecspanse.State
      def get_state! do
        case Ecspanse.Query.fetch_resource(__MODULE__) do
          {:ok, %__MODULE__{current: current_state}} when is_atom(current_state) ->
            current_state

          _ ->
            raise "Error getting the current state for #{Kernel.inspect(__MODULE__)}. The state must be initialized in the `Ecspanse.setup/1` function."
        end
      end

      @impl Ecspanse.State
      def set_state!(next_state) do
        unless is_atom(next_state) and next_state in @states do
          raise ArgumentError,
                "Invalid state for State: #{Kernel.inspect(__MODULE__)}. The state must be an atom from: #{Kernel.inspect(@states)}."
        end

        current_state = get_state!()
        {:ok, state_res} = Ecspanse.Query.fetch_resource(__MODULE__)

        Ecspanse.Command.update_resource!(state_res, current: next_state)

        Ecspanse.event(
          {
            Ecspanse.Event.StateTransition,
            module: __MODULE__, previous_state: current_state, current_state: next_state
          },
          batch_key: __MODULE__
        )

        :ok
      end
    end
  end
end
