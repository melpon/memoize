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

    ps =
      for _ <- 1..1000, into: %{} do
        {pid, ref} = Process.spawn(fun, [:monitor])
        {pid, ref}
      end

    for _ <- 1..1000 do
      receive do
        {:DOWN, ref, :process, pid, reason} ->
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
      assert_raise(RuntimeError, "failed", fn ->
        Memoize.Cache.get_or_run(:key, fn -> cache_raise(100, 20) end)
      end)
    end

    fun2 = fn ->
      assert 30 == Memoize.Cache.get_or_run(:key, fn -> cache_raise(100, 30) end)
    end

    ps =
      for n <- 1..1000, into: %{} do
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
        {:DOWN, ref, :process, pid, reason} ->
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

      3 ->
        # third call
        30
    end
  end

  @tag skip: System.get_env("MEMOIZE_TEST_MODE") != "Memoize.CacheStrategy.Default"
  test "at first call after cache is expired, new value is cached" do
    assert 10 ==
             Memoize.Cache.get_or_run(
               :key,
               fn -> cache_with_call_count(:key, 100) end,
               expires_in: 100
             )

    assert 10 ==
             Memoize.Cache.get_or_run(
               :key,
               fn -> cache_with_call_count(:key, 100) end,
               expires_in: 100
             )

    # wait to expire the cache
    Process.sleep(120)

    assert 20 ==
             Memoize.Cache.get_or_run(
               :key,
               fn -> cache_with_call_count(:key, 100) end,
               expires_in: 100
             )

    assert 20 ==
             Memoize.Cache.get_or_run(
               :key,
               fn -> cache_with_call_count(:key, 100) end,
               expires_in: 100
             )

    # wait to expire the cache
    Process.sleep(120)

    assert 30 ==
             Memoize.Cache.get_or_run(
               :key,
               fn -> cache_with_call_count(:key, 100) end,
               expires_in: 100
             )

    assert 30 ==
             Memoize.Cache.get_or_run(
               :key,
               fn -> cache_with_call_count(:key, 100) end,
               expires_in: 100
             )
  end

  @tag skip: System.get_env("MEMOIZE_TEST_MODE") != "Memoize.CacheStrategy.Default"
  test "after garbage_collect/0 is called, expired value is collected" do
    assert 10 ==
             Memoize.Cache.get_or_run(
               :key1,
               fn -> cache_with_call_count(:key1, 100) end,
               expires_in: 100
             )

    assert 10 == Memoize.Cache.get_or_run(:key3, fn -> cache_with_call_count(:key3, 0) end)
    # wait to expire the cache
    Process.sleep(120)
    # insert new value
    assert 10 ==
             Memoize.Cache.get_or_run(
               :key2,
               fn -> cache_with_call_count(:key2, 0) end,
               expires_in: 100
             )

    # :key1's value is collected
    assert 1 == Memoize.Cache.garbage_collect()

    assert 20 ==
             Memoize.Cache.get_or_run(
               :key1,
               fn -> cache_with_call_count(:key1, 0) end,
               expires_in: 100
             )

    assert 10 ==
             Memoize.Cache.get_or_run(
               :key2,
               fn -> cache_with_call_count(:key2, 0) end,
               expires_in: 100
             )

    assert 10 == Memoize.Cache.get_or_run(:key3, fn -> cache_with_call_count(:key3, 0) end)
  end

  def eat_memory(threshold) do
    try do
      for n <- 1..1_000_000 do
        assert 10 == Memoize.Cache.get_or_run(n, fn -> 10 end)

        if threshold <= Memoize.CacheStrategy.Eviction.used_bytes() do
          throw(:break)
        end
      end
    else
      _ -> raise "could not finish eating"
    catch
      :break -> :ok
    end
  end

  @tag skip: System.get_env("MEMOIZE_TEST_MODE") != "Memoize.CacheStrategy.Eviction"
  test "if the memory usage exceeds the max_threshold, unused cached values is evicted" do
    opts = Application.fetch_env!(:memoize, Memoize.CacheStrategy.Eviction)
    min_threshold = Keyword.fetch!(opts, :min_threshold)
    max_threshold = Keyword.fetch!(opts, :max_threshold)

    eat_memory(max_threshold - 100)
    assert max_threshold - 100 <= Memoize.CacheStrategy.Eviction.used_bytes()
    # read cached values to update last accessed time
    Memoize.Cache.get_or_run(1, fn -> 20 end)
    Memoize.Cache.get_or_run(2, fn -> 20 end)
    Memoize.Cache.get_or_run(3, fn -> 20 end)
    # still exceeded the threshold
    assert max_threshold - 100 <= Memoize.CacheStrategy.Eviction.used_bytes()

    # next inserting is occured garbage collection
    assert 10 == Memoize.Cache.get_or_run(:gc, fn -> 10 end)

    used_bytes = Memoize.CacheStrategy.Eviction.used_bytes()
    assert min_threshold - 100 <= used_bytes && used_bytes <= min_threshold + 100

    # below keys are still cached
    Memoize.Cache.get_or_run(1, fn -> 10 end)
    Memoize.Cache.get_or_run(2, fn -> 10 end)
    Memoize.Cache.get_or_run(3, fn -> 10 end)
    assert used_bytes == Memoize.CacheStrategy.Eviction.used_bytes()

    # below key is already collected
    Memoize.Cache.get_or_run(4, fn -> 10 end)
    assert used_bytes < Memoize.CacheStrategy.Eviction.used_bytes()
  end

  @tag skip: System.get_env("MEMOIZE_TEST_MODE") != "Memoize.CacheStrategy.Eviction"
  test "garbage_collect/0 collects memory until it falls below min_threshold" do
    opts = Application.fetch_env!(:memoize, Memoize.CacheStrategy.Eviction)
    min_threshold = Keyword.fetch!(opts, :min_threshold)

    eat_memory(min_threshold)
    assert min_threshold <= Memoize.CacheStrategy.Eviction.used_bytes()

    Memoize.Cache.get_or_run(:a, fn -> 10 end)
    Memoize.Cache.get_or_run(:b, fn -> 10 end)
    Memoize.Cache.get_or_run(:c, fn -> 10 end)
    Memoize.garbage_collect()

    used_bytes = Memoize.CacheStrategy.Eviction.used_bytes()
    assert min_threshold > used_bytes

    # no effect
    Memoize.garbage_collect()
    assert used_bytes == Memoize.CacheStrategy.Eviction.used_bytes()
  end

  @tag skip: System.get_env("MEMOIZE_TEST_MODE") != "Memoize.CacheStrategy.Eviction"
  test "if :permanent is specified in get_or_cache's opts, the cached value won't be collected by garbage_collect/0" do
    opts = Application.fetch_env!(:memoize, Memoize.CacheStrategy.Eviction)
    min_threshold = Keyword.fetch!(opts, :min_threshold)

    Memoize.Cache.get_or_run(:key, fn -> 10 end, permanent: true)
    eat_memory(min_threshold)
    Memoize.garbage_collect()

    # :key's value is not collected
    assert 10 == Memoize.Cache.get_or_run(:key, fn -> 20 end, permanent: true)
  end

  @tag skip: System.get_env("MEMOIZE_TEST_MODE") != "Memoize.CacheStrategy.Eviction"
  test "after expires_in milliseconds have elapsed, all expired value is collected" do
    assert 10 ==
             Memoize.Cache.get_or_run(
               :key,
               fn -> cache_with_call_count(:key, 0) end,
               expires_in: 100
             )

    assert 10 ==
             Memoize.Cache.get_or_run(
               :key2,
               fn -> cache_with_call_count(:key2, 0) end,
               expires_in: 200
             )

    # wait to expire the :key's cache
    Process.sleep(120)
    assert 20 == Memoize.Cache.get_or_run(:key, fn -> cache_with_call_count(:key, 0) end)
    assert 10 == Memoize.Cache.get_or_run(:key2, fn -> cache_with_call_count(:key2, 0) end)
    # wait to expire the :key2's cache
    Process.sleep(120)
    assert 20 == Memoize.Cache.get_or_run(:key, fn -> cache_with_call_count(:key, 0) end)
    assert 20 == Memoize.Cache.get_or_run(:key2, fn -> cache_with_call_count(:key2, 0) end)
  end

  @tag skip: System.get_env("MEMOIZE_TEST_MODE") != "Memoize.CacheStrategy.Eviction_2"
  test "if :max_threshold is :infinity, cached values are not collected caused by memory size" do
    eat_memory(10_000_000)
    used_bytes = Memoize.CacheStrategy.Eviction.used_bytes()
    Memoize.garbage_collect()
    assert used_bytes == Memoize.CacheStrategy.Eviction.used_bytes()
    # invalidates explicitly
    Memoize.invalidate()
    assert used_bytes > Memoize.CacheStrategy.Eviction.used_bytes()
  end
end
