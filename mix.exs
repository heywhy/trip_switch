defmodule TripSwitch.MixProject do
  use Mix.Project

  @version "0.1.0"
  @scm_url "https://github.com/heywhy/trip_switch"
  @docs_url "https://hexdocs.pm/trip_switch"

  def project do
    [
      app: :trip_switch,
      version: @version,
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      package: [
        files: ["lib", "mix.exs", "CHANGELOG.md", "README.md"],
        maintainers: ["Rasheed Atanda"],
        licenses: ["MIT"],
        links: %{
          "Docs" => @docs_url,
          "GitHub" => @scm_url
        }
      ],
      description: "A circuit breaker implementation for Elixir.",

      # Coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],

      # Dialyzer
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: []
      ],

      # Docs
      name: "TripSwitch",
      source_url: @scm_url,
      homepage_url: @docs_url,
      docs: [
        main: "TripSwitch",
        extras: ["README.md", "LICENSE"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {TripSwitch.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.6", only: :dev, runtime: false},
      {:dialyxir, "~> 1.2", only: :dev, runtime: false},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:excoveralls, "~> 0.15", only: :test},
      {:git_hooks, "~> 0.7", only: :dev, runtime: false},
      {:git_ops, "~> 2.5", only: :dev},
      {:telemetry, "~> 1.2"}
    ]
  end

  defp aliases do
    [
      "ops.release": ["cmd mix test --color", "git_ops.release"],
      setup: ["deps.get", "git_hooks.install"]
    ]
  end
end
