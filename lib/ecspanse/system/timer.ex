defmodule Ecspanse.System.Timer do
  @moduledoc """
  TODO
  Counts down the time for the Timer component.
  When the time reaches 0, the event is dispatched.
  If the mode is :repeat, the time is reset to the original duration.
  If the mode is :temporary, the Timer component is removed from the entity.


  This system needs to be manually added to the World setup as sync system.
  For more details check Ecspanse.Component.Timer.
  """

  use Ecspanse.System
  alias Ecspanse.Query

  @impl true
  def run(frame) do
    Query.list_group_components(:ecs_timer, frame.token)
    |> Stream.filter(fn timer -> timer.time > 0 and not timer.paused end)
    |> Enum.group_by(fn timer -> timer.mode end)
    |> Enum.each(fn
      {:repeat, timers} -> update_repeating(timers, frame)
      {:once, timers} -> update_once(timers, frame)
      {:temporary, timers} -> update_temporary(timers, frame)
    end)
  end

  defp update_repeating(timers, frame) do
    timers
    |> Enum.map(fn timer ->
      new_time = timer.time - frame.delta

      if new_time <= 0 do
        entity = Query.get_component_entity(timer, frame.token)
        event_spec = build_event_spec(timer, entity)
        Ecspanse.event(event_spec, frame.token, batch_key: entity.id)
        {timer, time: timer.duration + new_time}
      else
        {timer, time: new_time}
      end
    end)
    |> Ecspanse.Command.update_components!()
  end

  defp update_once(timers, frame) do
    timers
    |> Enum.map(fn timer ->
      new_time = max(timer.time - frame.delta, 0)

      if new_time == 0 do
        entity = Query.get_component_entity(timer, frame.token)
        event_spec = build_event_spec(timer, entity)
        Ecspanse.event(event_spec, frame.token, batch_key: entity.id)
      end

      {timer, time: new_time}
    end)
    |> Ecspanse.Command.update_components!()
  end

  defp update_temporary(timers, frame) do
    %{update: update, remove: remove} =
      timers
      |> Enum.reduce(%{update: [], remove: []}, fn timer, acc ->
        new_time = max(timer.time - frame.delta, 0)

        if new_time == 0 do
          entity = Query.get_component_entity(timer, frame.token)
          event_spec = build_event_spec(timer, entity)
          Ecspanse.event(event_spec, frame.token, batch_key: entity.id)
          %{acc | remove: [timer | acc.remove]}
        else
          %{acc | update: [{timer, time: new_time} | acc.update]}
        end
      end)

    Ecspanse.Command.update_components!(update)
    Ecspanse.Command.remove_component!(remove)
  end

  defp build_event_spec(timer, entity) do
    {timer.event, entity: entity}
  end
end
