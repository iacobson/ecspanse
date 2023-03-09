defmodule Ecspanse.MixProject do
  use Mix.Project

  def project do
    [
      app: :ecspanse,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:elixir_uuid, "~> 1.2"},
      {:plug_crypto, "~> 1.2"},
      {:ex2ms, "~> 1.6"},
      {:memoize, "~> 1.4"},
      {:rustler, "~> 0.27.0"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false}
    ]
  end
end
