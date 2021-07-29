defmodule Memoize.Case do
  use ExUnit.CaseTemplate

  def find_cache() do
    config = ExUnit.configuration()

    case Keyword.fetch(config, :include) do
      :error ->
        :error

      {:ok, kw} ->
        case Keyword.fetch(kw, :cache) do
          :error -> :error
          {:ok, value} -> {:ok, value}
        end
    end
  end

  defp put_envs(app, kvs) do
    for {k, v} <- kvs do
      Application.put_env(app, k, v)
    end

    on_exit(fn ->
      for {k, _} <- kvs do
        Application.delete_env(app, k)
      end
    end)
  end

  defp restart(app) do
    :ok = Application.stop(app)
    :ok = Application.start(app)
  end

  setup_all do
    case find_cache() do
      {:ok, "default"} ->
        :ok

      {:ok, "default_2"} ->
        # no cache mode
        put_envs(:memoize,
          cache_strategy: Memoize.CacheStrategy.Default,
          "Elixir.Memoize.CacheStrategy.Default": [
            expires_in: 0
          ]
        )

        restart(:memoize)

      {:ok, "eviction"} ->
        put_envs(:memoize,
          cache_strategy: Memoize.CacheStrategy.Eviction,
          "Elixir.Memoize.CacheStrategy.Eviction": [
            min_threshold: 90000,
            max_threshold: 100_000
          ]
        )

        restart(:memoize)

      {:ok, "eviction_2"} ->
        put_envs(:memoize,
          cache_strategy: Memoize.CacheStrategy.Eviction,
          "Elixir.Memoize.CacheStrategy.Eviction": [
            max_threshold: :infinity
          ]
        )

        restart(:memoize)

      {:ok, "waiter"} ->
        put_envs(:memoize,
          cache_strategy: Memoize.CacheStrategy.Default,
          max_waiters: 0,
          waiter_sleep_ms: 0
        )

        restart(:memoize)

      _ ->
        :ok
    end

    :ok
  end
end

ExUnit.start()
