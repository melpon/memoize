defmodule Memoize.Mixfile do
  use Mix.Project

  @source_url "https://github.com/melpon/memoize"
  @version "1.4.0"

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
      package: package(),
      aliases: aliases(),
      preferred_cli_env: preferred_cli_env()
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
      source_ref: "#{@version}",
      skip_undefined_reference_warnings_on: ["CHANGELOG.md", "README.md"]
    ]
  end

  @tests [
    :"test.default",
    :"test.default_2",
    :"test.eviction",
    :"test.eviction_2",
    :"test.waiter"
  ]

  defp aliases() do
    tests_fn = @tests |> Enum.map(fn test -> {test, &do_test(test, &1)} end)
    tests_str = @tests |> Enum.map(&Atom.to_string/1)
    ["test.all": tests_str] ++ tests_fn
  end

  defp preferred_cli_env() do
    @tests |> Enum.map(&{&1, :test})
  end

  defp do_test(name, args) do
    tag = name |> Atom.to_string() |> String.replace("test.", "cache:")

    mix_cmd_with_status_check(
      ["test", ansi_option()] ++ args ++ ["--exclude", "cache", "--include", tag]
    )
  end

  defp ansi_option do
    if IO.ANSI.enabled?(), do: "--color", else: "--no-color"
  end

  defp mix_cmd_with_status_check(args, opts \\ []) do
    {_, res} = System.cmd("mix", args, [into: IO.binstream(:stdio, :line)] ++ opts)

    if res > 0 do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end
end
