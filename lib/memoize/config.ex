defmodule Memoize.Config do
  @moduledoc false

  def init(opts) do
    :persistent_term.put(
      :memoize_cache_strategy,
      Keyword.get(
        opts,
        :cache_strategy,
        Application.get_env(:memoize, :cache_strategy, Memoize.CacheStrategy.Default)
      )
    )

    opts = Keyword.put_new(opts, :max_waiters, Application.get_env(:memoize, :max_waiters, 20))

    opts =
      Keyword.put_new(
        opts,
        :waiter_sleep_ms,
        Application.get_env(:memoize, :waiter_sleep_ms, 200)
      )

    opts = cache_strategy().init(opts)

    :persistent_term.put(:memoize_opts, Map.new(opts))
  end

  def cache_strategy() do
    :persistent_term.get(:memoize_cache_strategy)
  end

  def opts() do
    :persistent_term.get(:memoize_opts)
  end
end
