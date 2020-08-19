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
      docs: [main: "Memoize"],
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: "https://github.com/melpon/memoize"
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {Memoize.Application, []}]
  end

  defp deps do
    [{:ex_doc, "~> 0.19.1", only: :dev, runtime: false}, {:telemetry, "~> 0.4.2"}]
  end
end
