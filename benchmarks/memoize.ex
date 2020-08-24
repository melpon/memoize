defmodule Memoize.Benchmarks.Memoize do
  use Memoize
  alias Memoize.Benchmarks.Bench

  defmemo test(n, counter) do
    Bench.calc(n, counter)
    n
  end
end
