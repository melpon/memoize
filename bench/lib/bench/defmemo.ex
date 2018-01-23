defmodule Bench.Defmemo do
  import DefMemo

  defmemo test(n) do
    Bench.calc(n)
    n
  end
end
