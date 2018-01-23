defmodule Bench.Memoize do
  use Memoize

  defmemo test(n) do
    Bench.calc(n)
    n
  end
end
