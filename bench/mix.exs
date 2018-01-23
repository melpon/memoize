defmodule Bench.Mixfile do
  use Mix.Project

  def project do
    [
      app: :bench,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Bench.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:memoize, path: ".."},
      {:defmemo, "~> 0.1.1"},
      {:memoizer, "~> 0.1.0"},
      {:cachex, "~> 2.1"}
    ]
  end
end
