use Mix.Config

config :memoize,
  cache_strategy: Memoize.CacheStrategy.Eviction

config :memoize, Memoize.CacheStrategy.Eviction,
  max_threshold: :infinity
