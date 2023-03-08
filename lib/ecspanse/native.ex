defmodule Ecspanse.Native do
  @moduledoc """
  Rust NIFs for Ecspanse
  """
  use Rustler, otp_app: :ecspanse, crate: :ecspanse

  def list_entities_components(_list), do: error()

  defp error, do: :erlang.nif_error(:nif_not_loaded)
end
