use Mix.Config

case System.get_env("BENCH_CONFIG") do
  "" ->
    raise "set BENCH_CONFIG environment"

  "memoize.default" ->
    config :bench, module: Bench.Memoize

  "memoize.eviction" ->
    config :memoize, cache_strategy: Memoize.CacheStrategy.Eviction

    config :memoize, Memoize.CacheStrategy.Eviction, max_threshold: :infinity

    config :bench, module: Bench.Memoize

  "defmemo" ->
    config :bench, module: Bench.Defmemo

  "cachex" ->
    config :bench, module: Bench.Cachex
end

case System.get_env("BENCH_COUNT") do
  "" ->
    raise "set BENCH_COUNT environment"

  n ->
    config :bench, count: String.to_integer(n)
end
