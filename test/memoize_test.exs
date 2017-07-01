defmodule MemoizeTest do
  use ExUnit.Case
  doctest Memoize

  @tab __MODULE__
  @fun_lock :locked

  setup do
    :ets.new(@tab, [:public, :set, :named_table])
    :ets.insert(@tab, {@fun_lock, false})

    ExUnit.Callbacks.on_exit(fn -> Memoize.invalidate() end)

    :ok
  end


  test "get_or_run" do
    assert 10 == Memoize.get_or_run(:key, fn -> 10 end)
    assert 10 == Memoize.get_or_run(:key, fn -> 10 end)
    assert true == Memoize.invalidate(:key)
    assert false == Memoize.invalidate(:key)
    assert 10 == Memoize.get_or_run(:key, fn -> 10 end)
  end

  defp single_call(wait_time, result) do
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
            assert 20 == Memoize.get_or_run(:key, fn -> single_call(100, 20) end)
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
end
