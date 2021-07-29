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
      source_ref: "v#{@version}",
      skip_undefined_reference_warnings_on: ["CHANGELOG.md", "README.md"]
    ]
  end

  defp aliases() do
    [
      "test.all": ["test.default", "test.eviction", "test.eviction_2", "test.waiter"],
      "test.default": &test_default/1,
      "test.eviction": &test_eviction/1,
      "test.eviction_2": &test_eviction_2/1,
      "test.waiter": &test_waiter/1
    ]
  end

  defp preferred_cli_env() do
    [
      "test.all": :test,
      "test.default": :test,
      "test.eviction": :test,
      "test.eviction_2": :test,
      "test.waiter": :test
    ]
  end

  defp test_default(args) do
    mix_cmd_with_status_check(
      ["test", ansi_option()] ++ args ++ ["--exclude", "cache", "--include", "cache:default"]
    )
  end

  defp test_eviction(args) do
    Application.put_env(:memoize, :cache_strategy, Memoize.CacheStrategy.Eviction)

    Application.put_env(:memoize, Memoize.CacheStrategy.Eviction,
      min_threshold: 90000,
      max_threshold: 100_000
    )

    mix_cmd_with_status_check(
      ["test", ansi_option()] ++ args ++ ["--exclude", "cache", "--include", "cache:eviction"]
    )
  end

  defp test_eviction_2(args) do
    Application.put_env(:memoize, :cache_strategy, Memoize.CacheStrategy.Eviction)
    Application.put_env(:memoize, Memoize.CacheStrategy.Eviction, max_threshold: :infinity)

    mix_cmd_with_status_check(
      ["test", ansi_option()] ++ args ++ ["--exclude", "cache", "--include", "cache:eviction_2"]
    )
  end

  defp test_waiter(args) do
    Application.put_env(:memoize, :cache_strategy, Memoize.CacheStrategy.Default)
    Application.put_env(:memoize, :max_waiters, 0)
    Application.put_env(:memoize, :waiter_sleep_ms, 0)

    mix_cmd_with_status_check(
      ["test", ansi_option()] ++ args ++ ["--exclude", "cache", "--include", "cache:waiter"]
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
