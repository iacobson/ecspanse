defmodule Ecspanse.System.Timer do
  @moduledoc """
  A special system provided by the framework that
  counts down the time for all the custom timer components.

  If the `timer` functionality is used, this system
  needs to be manually added in the `c:Ecspanse.setup/1`
  callback as a sync system.

  See `Ecspanse.Template.Component.Timer` for details.
  """

  use Ecspanse.System
  alias Ecspanse.Query

  @impl true
  def run(frame) do
    Query.list_tagged_components([:ecs_timer])
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
        entity = Query.get_component_entity(timer)
        event_spec = build_event_spec(timer, entity)
        Ecspanse.event(event_spec, batch_key: entity.id)
        {timer, time: repeating_time(timer, new_time)}
      else
        {timer, time: new_time}
      end
    end)
    |> Ecspanse.Command.update_components!()
  end

  # ensure against negative time, when the frame takes longer than the timer duration
  defp repeating_time(timer, new_time) do
    time = timer.duration + new_time

    if time > 0 do
      time
    else
      timer.duration
    end
  end

  defp update_once(timers, frame) do
    timers
    |> Enum.map(fn timer ->
      new_time = max(timer.time - frame.delta, 0)

      if new_time == 0 do
        entity = Query.get_component_entity(timer)
        event_spec = build_event_spec(timer, entity)
        Ecspanse.event(event_spec, batch_key: entity.id)
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
          entity = Query.get_component_entity(timer)
          event_spec = build_event_spec(timer, entity)
          Ecspanse.event(event_spec, batch_key: entity.id)
          %{acc | remove: [timer | acc.remove]}
        else
          %{acc | update: [{timer, time: new_time} | acc.update]}
        end
      end)

    Ecspanse.Command.update_components!(update)
    Ecspanse.Command.remove_components!(remove)
  end

  defp build_event_spec(timer, entity) do
    {timer.event, entity_id: entity.id}
  end
end
