defmodule Ecspanse.Component.Timer do
  @moduledoc """
  The `Timer` is a **Utility Component** designed to facilitate the creation
  of custom timer (countdown) components.

  Instead of using this component directly, it serves as a foundation
  for building custom timer components with `use Ecspanse.Component.Timer`.

  The framework automatically decrements the Timer's time each frame,
  eliminating the need for manual updates.
  However, manual resetting may be necessary under certain circumstances such as:
  - When game logic requires custom resetting.
  - When the timer mode is set to `:once`, necessitating manual reset after reaching 0.

  A dedicated `Ecspanse.System.Timer` system is provided by the framework.
  This system auto-decrements the Timer component's time
  and dispatches an event when time reaches 0.
  To ensure functionality, this System must be manually included in the `c:Ecspanse.setup/1`.
  Note that it should be added as a sync system, either at frame start or end.
  This design choice allows developers control over timer operation
  based on specific states or conditions.
  For instance, pausing the timers when the game is in a pause state or other game states.

  Pause control at a granular level can be achieved by setting the `paused` field to true.

  The Timer component comes with a **predefined state** comprising of:
  - `:duration` - the timer's duration in milliseconds which also serves
  as the reset value.
  - `:time` - the current time of the timer in milliseconds,
  auto-decremented by the framework each frame.
  - `:event` - the event module dispatched when timer reaches 0.
    - create special timer events using `Ecspanse.Event.Timer`.
    - these events require no options.
    - their state is predefined to `%CustomEventModule{entity_id: entity_id}`,
    where entity refers to owner of the custom timer component.
    - event batch key corresponds to the component's owner entity's id.
  - `:mode` - defines how timer operates and can be one of:
    - `:repeat` (default) - timer resets to original duration
    after reaching 0 and repeats indefinitely.
    - `:once` - timer runs once and pauses after reaching 0.
    Time value needs manual reset.
    - `:temporary`: Timer runs once and removes itself from entity after reaching 0.
  - `paused`: A boolean indicating if timer is paused (defaults to false).


  ## Example:

    ```elixir
    defmodule MyTimerComponent do
      use Ecspanse.Component.Timer,
        state: [duration: 3000, event: MyTimerEvent, mode: :repeat, paused: false]
    end

    defmodule MyTimerEvent do
      use Ecspanse.Event.Timer
    end
  end
  ```

  See [a working example](./tutorial.md#energy-regeneration) in the tutorial

  """
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      tags = Keyword.get(opts, :tags, []) ++ [:ecs_timer]

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
        tags: tags,
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
