defmodule Ecspanse.Component.Timer do
  @moduledoc """
  TODO
  Utility Component to create custom timer (countdown) components.

  This component should not be used as such, but as a builder of custom timer components.


  The time is the Timer is automatically decremented by the framework each frame.
  There is no need to update the component's time manually. Except when:
  - it requires custom reseting by the game logic
  - the timer mode is set to :once, and requires to be reset manually after reaching 0

  There is a special Ecspanse.System.Timer system provided by the framework that
  automatically decrements the time of the Timer component and dispatches the event when the time reaches 0.
  This System needs to be manually added in the systems setup, otherwise the timer will not work.
  Attention! the System meeds to be added as sync, as frame start system of frame end system.
  This is a deliberate decision, to allow the developer to decide if the timers shuld run only in
  cetain states or certain conditions. For example, the developer might want to pause the timers
  when the game is paused, or when the game is in a certain state.

  Granular pause control can be achieved by setting the paused field to true.

  Example:
    defmodule MyTimerComponent do
      use Ecspanse.Component.Timer,
        state: [duration: 3000, event: MyTimerEvent, mode: :repeat, paused: false]
    end

    defmodule MyTimerEvent do
      use Ecspanse.Event.Timer
    end
  end


  The Timer component has a predefined state with the following fields:
    - duration: the duration of the timer in milliseconds. This is the value that will be used to reset the timer.
    - time: the current time of the timer in milliseconds. This value is automatically decremented by the framework each frame.
    - event: the event module that will be dispatched when the timer reaches 0.
      - special Timer events should be created using the Ecspanse.Event.Timer module
      - they take no options
      - the state of those events is %MyTimerEvent{entity_id: entity_id}. The entity is the owner of the Timer compoenent.
      - the event batch key is set to the id of the owner entity.
    - mode: the mode of the timer. Can be one of the following:
      - :repeat (default) - the timer will repeat itself indefinitely. After reaching 0, the timer will be reset to its original duration.
      - :once - the timer will run only once. After reaching 0, the timer will be paused. Its time value needs to be reset manually.
      - :temporary - the timer will run only once. After reaching 0, the timer will be removed from the entity.
    - paused: a boolean value that indicates if the timer is paused or not. Defaults to false.

  """
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      groups = Keyword.get(opts, :groups, []) ++ [:ecs_timer]

      state = Keyword.get(opts, :state, [])

      unless is_list(state) do
        raise ArgumentError,
              "Invalid state for Component: #{inspect(__MODULE__)}. The `:state` option must be a list with all the Component state struct keys and their initial values (if any). Eg: [:foo, :bar, baz: 1]"
      end

      duration = Keyword.get(state, :duration)

      unless duration && is_integer(duration) && duration > 0 do
        raise ArgumentError,
              "Invalid duration for Timer Component: #{inspect(__MODULE__)}. The `:duration` is mandatory in the Timer state and must be a positive integer."
      end

      time = duration

      event = Keyword.get(state, :event)

      unless event && is_atom(event) do
        raise ArgumentError,
              "Invalid event for Timer Component: #{inspect(__MODULE__)}. The `:event` is mandatory in the Timer state and must point to the event module that will be dispatched when the time reaches 0."
      end

      mode = Keyword.get(state, :mode, :repeat)

      unless mode in [:repeat, :once, :temporary] do
        raise ArgumentError,
              "Invalid mode for Timer Component: #{inspect(__MODULE__)}. The `:mode` must be one of the following: :repeat, :once, :temporary."
      end

      paused = Keyword.get(state, :paused, false)

      unless is_boolean(paused) do
        raise ArgumentError,
              "Invalid paused value for Timer Component: #{inspect(__MODULE__)}. The `:paused` must be a boolean value."
      end

      use Ecspanse.Component,
        groups: groups,
        state: [
          duration: duration,
          time: time,
          event: event,
          mode: mode,
          paused: paused
        ]

      @type t :: %__MODULE__{
              duration: integer(),
              time: integer(),
              event: module(),
              mode: :repeat | :once | :temporary,
              paused: boolean()
            }
    end
  end
end
