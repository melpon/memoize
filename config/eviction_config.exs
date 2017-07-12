use Mix.Config

config :memoize,
  memory_strategy: Memoize.MemoryStrategy.Eviction

config :memoize, Memoize.MemoryStrategy.Eviction,
  min_threshold: 90000,
  max_threshold: 100000
