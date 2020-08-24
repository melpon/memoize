defmodule Memoize.Mixfile do
  use Mix.Project
  def project do
    [
      app: :memoize,
      version: "1.3.1",
      elixir: "~> 1.5",
      description: "A method caching macro for elixir using CAS on ETS",
      package: [
        maintainers: ["melpon"],
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/melpon/memoize"}
      ],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
	bench: :bench,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      dialyzer: [
        plt_add_deps: :transitive,
        plt_add_apps: [:ex_unit, :mix]
      ],
      docs: [main: "Memoize"],
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      source_url: "https://github.com/melpon/memoize",
      aliases: aliases()
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:bench), do: ["lib", "benchmarks"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      bench: ["run benchmarks/run.exs"]
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {Memoize.Application, []}]
  end

  defp deps do
    [
      {:telemetry, "~> 0.4.2"},
      {:ex_doc, "~> 0.19.1", only: :dev, runtime: false},
      {:benchee, "~> 1.0", only: :bench},
      {:benchee_html, "~> 1.0", only: :bench},
      {:benchee_markdown, "~> 0.2.4", only: :bench},
      {:credo, "~> 1.1.0", only: [:dev, :test, :bench], runtime: false},
      {:dialyxir, "~> 1.0.0", only: [:dev, :test, :bench], runtime: false},
      {:excoveralls, "~> 0.10", only: [:dev, :test, :bench]},
      {:cachex, "~> 3.3", only: :bench},
    ]
  end
end
