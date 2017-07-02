defmodule Memoize.Cache do
  @moduledoc false

  defp tab() do
    Memoize.Application.tab()
  end

  defp compare_and_swap(:nothing, value) do
    :ets.insert_new(tab(), value)
  end

  defp compare_and_swap(expected, :nothing) do
    num_deleted = :ets.select_delete(tab(), [{expected, [], [true]}])
    num_deleted == 1
  end

  defp compare_and_swap(expected, value) do
    num_replaced = :ets.select_replace(tab(), [{expected, [], [{:const, value}]}])
    num_replaced == 1
  end

  defp set_result_and_get_waiter_pids(key, result, expires_in) do
    runner_pid = self()
    [{^key, {:running, ^runner_pid, waiter_pids}} = expected] = :ets.lookup(tab(), key)
    expired_at = case expires_in do
                   :infinity -> :infinity
                   value -> System.monotonic_time(:millisecond) + value
                 end
    if compare_and_swap(expected, {key, {:completed, result, expired_at}}) do
      waiter_pids
    else
      # retry
      set_result_and_get_waiter_pids(key, result, expires_in)
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

  def get_or_run(key, fun, opts \\ []) do
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
              expires_in = Keyword.get(opts, :expires_in, :infinity)
              waiter_pids = set_result_and_get_waiter_pids(key, result, expires_in)
              Enum.map(waiter_pids, fn {pid, _} ->
                                      send(pid, {self(), :completed})
                                    end)
              result
          rescue
            error ->
              # the status should be :running
              waiter_pids = delete_and_get_waiter_pids(key)
              Enum.map(waiter_pids, fn {pid, _} ->
                                      send(pid, {self(), :failed})
                                    end)
              reraise error, System.stacktrace()
          end
        else
          get_or_run(key, fun)
        end

      # running
      [{^key, {:running, runner_pid, waiter_pids}} = expected] ->
        waiter_pids = Map.put(waiter_pids, self(), :ignore)
        if compare_and_swap(expected, {key, {:running, runner_pid, waiter_pids}}) do
          ref = Process.monitor(runner_pid)
          receive do
            {^runner_pid, :completed} -> :ok
            {^runner_pid, :failed} -> :ok
            {:"DOWN", ^ref, :process, ^runner_pid, _reason} -> :ok
          after
            5000 -> :ok
          end

          Process.demonitor(ref, [:flush])
          # flush existing messages
          receive do
            {^runner_pid, _} -> :ok
          after
            0 -> :ok
          end

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

  def invalidate() do
    :ets.select_delete(tab(), [{{:_, {:completed, :_, :_}}, [], [true]}])
  end

  def invalidate(key) do
    :ets.select_delete(tab(), [{{key, {:completed, :_, :_}}, [], [true]}])
  end
end
