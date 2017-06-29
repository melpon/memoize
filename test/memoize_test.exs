defmodule MemoizeTest do
  use ExUnit.Case
  doctest Memoize

  test "get_or_run" do
    assert 10 == Memoize.get_or_run(:key, fn -> 10 end)
    assert 10 == Memoize.get_or_run(:key, fn -> 10 end)
    assert true == Memoize.invalidate(:key)
    assert false == Memoize.invalidate(:key)
    assert 10 == Memoize.get_or_run(:key, fn -> 10 end)
  end
end
