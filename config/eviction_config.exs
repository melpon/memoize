use Mix.Config

config :memoize, cache_strategy: Memoize.CacheStrategy.Eviction

config :memoize, Memoize.CacheStrategy.Eviction,
  min_threshold: 90000,
  max_threshold: 100_000
