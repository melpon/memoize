defmodule MemoizeTest do
  use ExUnit.Case

  use Memoize

  defmemo foo(x, y) when x == 0 do
    y
  end

  defmemo foo(1, y) do
    y * 2
  end

  defmemo foo(x, y, z \\ 0) when x == 2 do
    y * z
  end

  test "defmemo defines foo" do
    assert 2 == foo(0, 2)
    assert 8 == foo(1, 4)
    assert 0 == foo(2, 4)
    assert 40 == foo(2, 4, 10)
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

  defmemo nothing_do(x)
  defmemo nothing_do(x) when x == 0, do: 0
  defmemo nothing_do(x) when x == 1, do: x * 2

  test "even if the `def` function has not `do`, defmemo is passed" do
    assert 0 == nothing_do(0)
    assert 2 == nothing_do(1)
  end

  defmemo has_expire(pid), expires_in: 100 do
    send(pid, :ok)
  end

  @tag skip: Memoize.cache_strategy() != Memoize.CacheStrategy.Default
  test "defmemo with expire" do
    assert :ok == has_expire(self())
    assert_received :ok

    # cached
    assert :ok == has_expire(self())
    refute_received _

    # wait to expire
    Process.sleep(120)
    assert :ok == has_expire(self())
    assert_received :ok

    # cached
    assert :ok == has_expire(self())
    refute_received _
  end

  defmodule Tarai do
    use Memoize
    defmemo tarai(x, y, _z) when x <= y, do: y
    defmemo tarai(x, y, z) do
      tarai(tarai(x - 1, y, z),
            tarai(y - 1, z, x),
            tarai(z - 1, x, y))
    end
  end

  test "tarai" do
    assert 12 == Tarai.tarai(12, 6, 0)
  end
end
