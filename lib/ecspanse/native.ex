defmodule Ecspanse.Native do
  @moduledoc """
  Rust NIFs for Ecspanse
  """
  use Rustler, otp_app: :ecspanse, crate: :ecspanse

  def list_entities_components(_list), do: error()
  def query_filter_for_entities(_entities_components, _filter_entities), do: error()
  def query_filter_not_for_entities(_entities_components, _reject_entities), do: error()

  defp error, do: :erlang.nif_error(:nif_not_loaded)
end
