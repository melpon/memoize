defmodule Memoize.Mixfile do
  use Mix.Project

  @source_url "https://github.com/melpon/memoize"
  @version "1.3.3"

  def project do
    [
      app: :memoize,
      version: @version,
      elixir: "~> 1.9",
      description: "A method caching macro for elixir using CAS on ETS",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Memoize.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["melpon"],
      licenses: ["MIT"],
      links: %{
        "Changelog" => "https://hexdocs.pm/memoize",
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      extras: ["CHANGELOG.md", "README.md"],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      skip_undefined_reference_warnings_on: ["CHANGELOG.md", "README.md"]
    ]
  end
end
