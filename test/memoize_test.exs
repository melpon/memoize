defmodule MemoizeTest do
  use ExUnit.Case

  use Memoize

  defmemo foo(x, y) when x == 0 do
    y
  end

  defmemo foo(x, y, z \\ 0) when x == 1 do
    y * z
  end

  test "defmemo defines foo" do
    assert 2 == foo(0, 2)
    assert 0 == foo(1, 4)
    assert 40 == foo(1, 4, 10)
  end

  defmemo bar(x, y) do
    x + y
  end

  defmemo bar(x, y, z) do
    x + y + z
  end

  test "defmemo defines bar" do
    assert 3 == bar(1, 2)
    assert 7 == bar(1, 2, 4)
  end

  defmemop pri() do
    10
  end

  test "defmemop defines pri" do
    assert 10 == pri()
  end

  test "invalidates cached values when call invalidate/{0-3}" do
    f = fn -> 10 end

    Memoize.Cache.invalidate()
    Memoize.Cache.get_or_run({:mod1, :fun1, [1]}, f)
    Memoize.Cache.get_or_run({:mod1, :fun1, [2]}, f)
    Memoize.Cache.get_or_run({:mod1, :fun2, [1]}, f)
    Memoize.Cache.get_or_run({:mod2, :fun1, [1]}, f)

    assert 1 == Memoize.invalidate(:mod1, :fun1, [1])
    assert 1 == Memoize.invalidate(:mod1, :fun1)
    assert 1 == Memoize.invalidate(:mod1)
    assert 1 == Memoize.invalidate()
  end
end
