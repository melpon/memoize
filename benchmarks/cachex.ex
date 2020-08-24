defmodule Memoize.Benchmarks.Cachex do
  alias Memoize.Benchmarks.Bench

  def test(n, counter) do
    Cachex.transaction!(:my_cache, [n], fn state ->
      case Cachex.get(state, n) do
        {:ok, value} ->
          value

        {:missing, _} ->
          Bench.calc(n, counter)
          Cachex.set!(state, n, n)
          n
      end
    end)
  end
end
