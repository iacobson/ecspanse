defmodule Ecspanse.Template.Component.Timer do
  @moduledoc """
  The `Timer` is a **Template Component** designed to facilitate the creation
  of custom timer (countdown) components.

  It serves as a foundation for building custom timer components with `use Ecspanse.Template.Component.Timer`.

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

  The Timer component template comes with a **predefined state** comprising of:
  - `:duration` - the timer's duration in milliseconds which also serves
  as the reset value.
  - `:time` - the current time of the timer in milliseconds,
  auto-decremented by the framework each frame.
  - `:event` - the event module dispatched when timer reaches 0.
    - create special timer events using `Ecspanse.Template.Event.Timer`.
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
  - `paused`: A boolean indicating if timer is paused (defaults to `false`).


  ## Example:

    ```elixir
    defmodule Demo.Components.RestoreEnergyTimer do
      use Ecspanse.Template.Component.Timer,
        state: [duration: 3000, time: 3000, event: Demo.Events.RestoreEnergy, mode: :repeat, paused: false]
    end

    defmodule Demo.Events.RestoreEnergy do
      use Ecspanse.Template.Template.Event.Timer
    end
  end
  ```

  See [a working example](./tutorial.md#energy-regeneration) in the tutorial

  """
  use Ecspanse.Template.Component,
    tags: [:ecs_timer],
    state: [:duration, :time, :event, mode: :repeat, paused: false]

  @mode [:repeat, :once, :temporary]

  @impl true
  def validate(state) do
    with :ok <- validate_duration(state[:duration]),
         :ok <- validate_time(state[:time]),
         :ok <- validate_event(state[:event]),
         :ok <- validate_mode(state[:mode]),
         :ok <- validate_paused(state[:paused]) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_duration(duration) do
    if is_integer(duration) && duration > 0 do
      :ok
    else
      raise ArgumentError,
            "Invalid duration for Timer Component: #{inspect(__MODULE__)}. The `:duration` field is mandatory in the timer state and must be a positive integer."
    end
  end

  defp validate_time(time) do
    if is_integer(time) && time >= 0 do
      :ok
    else
      raise ArgumentError,
            "Invalid time for Timer Component: #{inspect(__MODULE__)}. The `:time` field is mandatory in the timer state and must be a non-negative integer."
    end
  end

  defp validate_event(event) do
    if is_atom(event) do
      :ok
    else
      raise ArgumentError,
            "Invalid event for Timer Component: #{inspect(__MODULE__)}. The `:event` field is mandatory in the timer state and must be an atom."
    end
  end

  defp validate_mode(mode) do
    if mode in @mode do
      :ok
    else
      raise ArgumentError,
            "Invalid mode for Timer Component: #{inspect(__MODULE__)}. The `:mode` field is mandatory in the timer state and must be one of the following: #{inspect(@mode)}"
    end
  end

  defp validate_paused(paused) do
    if is_boolean(paused) do
      :ok
    else
      raise ArgumentError,
            "Invalid paused for Timer Component: #{inspect(__MODULE__)}. The `:paused` field is mandatory in the timer state and must be a boolean."
    end
  end
end
