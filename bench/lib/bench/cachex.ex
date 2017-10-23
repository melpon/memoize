defmodule Bench.Cachex do
  def test(n) do
    Cachex.transaction!(:my_cache, [n], fn state ->
      case Cachex.get(state, n) do
        {:ok, value} -> value
        {:missing, _} ->
          Bench.calc(n)
          Cachex.set!(state, n, n)
          n
      end
    end)
  end
end
