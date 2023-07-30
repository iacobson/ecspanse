defmodule Ecspanse.System.Debug do
  @moduledoc """
  Generic system to be used by the `Ecspanse.System.debug/0` in dev and test environments.
  """
  use Ecspanse.System

  @impl true
  def run(_frame) do
  end
end
