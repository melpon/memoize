defmodule Memoize do
  defp tab() do
    Memoize.Application.tab()
  end

  defp compare_and_swap(:nothing, value) do
    :ets.insert_new(tab(), value)
  end

  defp compare_and_swap(expected, :nothing) do
    num_deleted = :ets.select_delete(tab(), [{:"$1", [{:"=:=", expected, :"$1"}], [true]}])
    num_deleted == 1
  end

  defp compare_and_swap(expected, value) do
    num_replaced = :ets.select_replace(tab(), [{expected, [], [{:const, value}]}])
    num_replaced == 1
  end

  defp set_result_and_get_waiter_pids(key, result) do
    runner_pid = self()
    [{^key, {:running, ^runner_pid, waiter_pids}} = expected] = :ets.lookup(tab(), key)
    if compare_and_swap(expected, {key, {:completed, result, :infinity}}) do
      waiter_pids
    else
      # retry
      set_result_and_get_waiter_pids(key, result)
    end
  end

  defp delete_and_get_waiter_pids(key) do
    runner_pid = self()
    [{^key, {:running, ^runner_pid, waiter_pids}} = expected] = :ets.lookup(tab(), key)
    if compare_and_swap(expected, :nothing) do
      waiter_pids
    else
      # retry
      delete_and_get_waiter_pids(key)
    end
  end

  def get_or_run(key, fun) do
    case :ets.lookup(tab(), key) do
      # not started
      [] ->
        # calc
        runner_pid = self()
        if compare_and_swap(:nothing, {key, {:running, runner_pid, %{}}}) do
          try do
            fun.()
          else
            result ->
              waiter_pids = set_result_and_get_waiter_pids(key, result)
              Enum.map(waiter_pids, fn {pid, _} ->
                                      send(pid, {tab(), key, :completed})
                                    end)
              result
          rescue
            error ->
              # the status should be :running
              waiter_pids = delete_and_get_waiter_pids(key)
              Enum.map(waiter_pids, fn {pid, _} ->
                                      send(pid, {tab(), key, :failed})
                                    end)
              reraise error, System.stacktrace()
          end
        else
          get_or_run(key, fun)
        end

      # running
      [{^key, {:running, runner_pid, waiter_pids} = expected}] ->
        waiter_pids = Map.put(waiter_pids, self(), :ignore)
        if compare_and_swap(expected, {key, {:running, runner_pid, waiter_pids}}) do
          ref = Process.monitor(runner_pid)
          tab = tab()
          receive do
            {^tab, ^key, :completed} -> :ok
            {^tab, ^key, :failed} -> :ok
            {:"DOWN", ^ref, :process, ^runner_pid, _reason} -> :ok
          after
            5000 -> :ok
          end

          Process.demonitor(ref)
          get_or_run(key, fun)
        else
          get_or_run(key, fun)
        end

      # completed
      [{^key, {:completed, value, expired_at}}] ->
        if expired_at != :infinity && System.monotonic_time(:millisecond) > expired_at do
          invalidate(key)
          get_or_run(key, fun)
        else
          value
        end
    end
  end

  def invalidate(key) do
    num_deleted = :ets.select_delete(tab(), [{{key, {:completed, :_, :_}}, [], [true]}])
    num_deleted == 1
  end
end
