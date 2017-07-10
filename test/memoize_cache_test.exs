defmodule Memoize.CacheTest do
  use ExUnit.Case

  @tab __MODULE__
  @fun_lock :fun_lock
  @call_count :call_count

  setup do
    :ets.new(@tab, [:public, :set, :named_table])
    :ets.insert(@tab, {@fun_lock, false})
    :ets.insert(@tab, {@call_count, 0})

    ExUnit.Callbacks.on_exit(fn -> Memoize.Cache.invalidate() end)

    :ok
  end

  test "get_or_run" do
    assert 10 == Memoize.Cache.get_or_run(:key, fn -> 10 end)
    assert 10 == Memoize.Cache.get_or_run(:key, fn -> 10 end)
    assert 1 == Memoize.Cache.invalidate(:key)
    assert 0 == Memoize.Cache.invalidate(:key)
    assert 10 == Memoize.Cache.get_or_run(:key, fn -> 10 end)
  end

  defp cache_single(wait_time, result) do
    case :ets.lookup(@tab, @fun_lock) do
      [{@fun_lock, false}] ->
        :ets.insert(@tab, {@fun_lock, true})
        Process.sleep(wait_time)
        :ets.insert(@tab, {@fun_lock, false})
        result
      _ ->
        raise "not single"
    end
  end

  test "many processes call get_or_run, but one process only calls the caching function" do
    fun = fn ->
            assert 20 == Memoize.Cache.get_or_run(:key, fn -> cache_single(100, 20) end)
          end

    ps = for _ <- 1..1000, into: %{} do
           {pid, ref} = Process.spawn(fun, [:monitor])
           {pid, ref}
         end

    for _ <- 1..1000 do
      receive do
        {:"DOWN", ref, :process, pid, reason} ->
          assert ps[pid] == ref
          assert reason == :normal
      end
    end
  end

  defp cache_raise(wait_time, result) do
    case :ets.update_counter(@tab, @call_count, {2, 1}) do
      1 ->
        # first call is failed
        Process.sleep(wait_time)
        raise "failed"
      _ ->
        # other calls are passed
        Process.sleep(wait_time)
        result
    end
  end

  test "if caching process is crashed when waiting many processes, one of the processes call the caching function" do
    fun1 = fn ->
             assert_raise(RuntimeError, "failed", fn -> Memoize.Cache.get_or_run(:key, fn -> cache_raise(100, 20) end) end)
           end

    fun2 = fn ->
             assert 30 == Memoize.Cache.get_or_run(:key, fn -> cache_raise(100, 30) end)
           end

    ps = for n <- 1..1000, into: %{} do
           # raise an exception at first call
           if n == 1 do
             {pid, ref} = Process.spawn(fun1, [:monitor])
             Process.sleep(10)
             {pid, ref}
           else
             {pid, ref} = Process.spawn(fun2, [:monitor])
             {pid, ref}
           end
         end

    for _ <- 1..1000 do
      receive do
        {:"DOWN", ref, :process, pid, reason} ->
          assert ps[pid] == ref
          assert reason == :normal
      end
    end
  end

  defp cache_with_call_count(key, wait_time) do
    Process.sleep(wait_time)
    case :ets.update_counter(@tab, {@call_count, key}, {2, 1}, {{@call_count, key}, 0}) do
      1 ->
        # first call
        10
      2 ->
        # second call
        20
    end
  end

  test "at first call after cache is expired, new value is cached" do
    assert 10 == Memoize.Cache.get_or_run(:key, fn -> cache_with_call_count(:key, 100) end, expires_in: 100)
    assert 10 == Memoize.Cache.get_or_run(:key, fn -> cache_with_call_count(:key, 100) end, expires_in: 100)
    # wait to expire the cache
    Process.sleep(120)
    assert 20 == Memoize.Cache.get_or_run(:key, fn -> cache_with_call_count(:key, 100) end, expires_in: 100)
    assert 20 == Memoize.Cache.get_or_run(:key, fn -> cache_with_call_count(:key, 100) end, expires_in: 100)
  end

  test "after garbage_collect/0 is called, expired value is collected" do
    assert 10 == Memoize.Cache.get_or_run(:key1, fn -> cache_with_call_count(:key1, 100) end, expires_in: 100)
    assert 10 == Memoize.Cache.get_or_run(:key3, fn -> cache_with_call_count(:key3, 0) end)
    # wait to expire the cache
    Process.sleep(120)
    # insert new value
    assert 10 == Memoize.Cache.get_or_run(:key2, fn -> cache_with_call_count(:key2, 0) end, expires_in: 100)
    # :key1's value is collected
    assert 1 == Memoize.Cache.garbage_collect()

    assert 20 == Memoize.Cache.get_or_run(:key1, fn -> cache_with_call_count(:key1, 0) end, expires_in: 100)
    assert 10 == Memoize.Cache.get_or_run(:key2, fn -> cache_with_call_count(:key2, 0) end, expires_in: 100)
    assert 10 == Memoize.Cache.get_or_run(:key3, fn -> cache_with_call_count(:key3, 0) end)
  end
end
