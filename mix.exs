defmodule Ecspanse.MixProject do
  use Mix.Project

  @version "0.1.2"
  @source_url "https://github.com/iacobson/ecspanse"

  def project do
    [
      app: :ecspanse,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      # hex
      description: description(),
      package: package(),

      # docs
      name: "ECSpanse",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:elixir_uuid, "~> 1.2"},
      {:ex2ms, "~> 1.6"},
      {:memoize, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.30.0", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "Ecspanse",
      source_ref: "v#{@version}",
      logo: "guides/images/logo.png",
      extra_section: "GUIDES",
      source_url: @source_url,
      extras: [
        "guides/getting_started.md",
        "guides/tutorial.md",
        "CHANGELOG.md"
      ],
      groups_for_docs: [
        Generic: &(&1[:group] == :generic),
        Entities: &(&1[:group] == :entities),
        Relationships: &(&1[:group] == :relationships),
        Components: &(&1[:group] == :components),
        Resources: &(&1[:group] == :resources),
        Tags: &(&1[:group] == :tags)
      ],
      nest_modules_by_prefix: [
        Ecspanse.Entity,
        Ecspanse.Component,
        Ecspanse.System,
        Ecspanse.Resource,
        Ecspanse.Event,
        Ecspanse.Query,
        Ecspanse.Command
      ],
      groups_for_modules: [
        API: [
          Ecspanse,
          Ecspanse.Data,
          Ecspanse.Frame,
          Ecspanse.Server,
          Ecspanse.Server.State,
          Ecspanse.TestServer
        ],
        Entities: [Ecspanse.Entity],
        Components: [
          Ecspanse.Component,
          Ecspanse.Component.Children,
          Ecspanse.Component.Parents,
          Ecspanse.Component.Timer
        ],
        Systems: [
          Ecspanse.System,
          Ecspanse.System.WithEventSubscriptions,
          Ecspanse.System.WithoutEventSubscriptions,
          Ecspanse.System.CreateDefaultResources,
          Ecspanse.System.Timer,
          Ecspanse.System.TrackFPS,
          Ecspanse.System.Debug
        ],
        Resources: [Ecspanse.Resource, Ecspanse.Resource.State, Ecspanse.Resource.FPS],
        Events: [
          Ecspanse.Event,
          Ecspanse.Event.ComponentCreated,
          Ecspanse.Event.ComponentUpdated,
          Ecspanse.Event.ComponentDeleted,
          Ecspanse.Event.ResourceCreated,
          Ecspanse.Event.ResourceUpdated,
          Ecspanse.Event.ResourceDeleted,
          Ecspanse.Event.Timer
        ],
        Queries: [Ecspanse.Query],
        Commands: [Ecspanse.Command]
      ]
    ]
  end

  defp package() do
    [
      maintainers: ["Dorian Iacobescu"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  def description do
    """
    Ecspanse is an Entity Component System (ECS) library for Elixir,
    offering a suite of features including:
    flexible queries with multiple filters,
    dynamic bidirectional relationships,
    versatile tagging capabilities,
    system event subscriptions,
    or asynchronous system execution.
    """
  end
end
