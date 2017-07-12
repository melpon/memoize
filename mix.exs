defmodule Memoize.Mixfile do
  use Mix.Project

  def project do
    [app: :memoize,
     version: "1.1.1",
     elixir: "~> 1.4.5",
     description: "A memoization macro for elixir using CAS on ETS",
     package: [maintainers: ["melpon"],
               licenses: ["MIT"],
               links: %{"GitHub" => "https://github.com/melpon/memoize"}],
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [extra_applications: [:logger],
     mod: {Memoize.Application, []}]
  end

  defp deps do
    [{:ex_doc, "~> 0.16.2", only: :dev}]
  end
end
