defmodule Memoize.Cache do
  @moduledoc """
  Module documentation for Memoize.Cache.
  """

  defp cache_strategy() do
    Memoize.Config.cache_strategy()
  end

  defp tab(key) do
    cache_strategy().tab(key)
  end

  defp compare_and_swap(key, :nothing, value, :ets) do
    :ets.insert_new(tab(key), value)
  end

  defp compare_and_swap(key, expected, :nothing, :ets) do
    num_deleted = :ets.select_delete(tab(key), [{expected, [], [true]}])
    num_deleted == 1
  end

  defp compare_and_swap(key, expected, value, :ets) do
    num_replaced = :ets.select_replace(tab(key), [{expected, [], [{:const, value}]}])
    num_replaced == 1
  end

  #----------------------persistent_term------------------
  defp compare_and_swap(key, :nothing, value, :persistent_term) do
    :persistent_term.put(key, value)

    true
  end

  defp compare_and_swap(key, _, :nothing, :persistent_term) do
    :ets.delete(tab(key), key)
    :persistent_term.erase(key)
  end

  defp compare_and_swap(key, _, value, :persistent_term) do
    :persistent_term.put(key, value)

    to_be_expired = value |> elem(1) |> elem(2)

    :ets.insert(tab(key), {key, to_be_expired, :persistent_term})
  end
  #^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

  defp set_result_and_get_waiter_pids(key, result, context, :ets) do
    runner_pid = self()
    [{^key, {:running, ^runner_pid, waiter_pids}} = expected] = :ets.lookup(tab(key), key)

    if compare_and_swap(key, expected, {key, {:completed, result, context}}, :ets) do
      waiter_pids
    else
      # retry
      set_result_and_get_waiter_pids(key, result, context, :ets)
    end
  end

  #-------------------persistent_term------------------
  defp set_result_and_get_waiter_pids(key, result, context, :persistent_term) do
    runner_pid = self()

    :persistent_term.get(key, [])
    |> case do
      {^key, {:running, ^runner_pid, waiter_pids}} = expected ->
        if compare_and_swap(key, expected, {key, {:completed, result, context}}, :persistent_term) do
          waiter_pids
        else
          # retry
          set_result_and_get_waiter_pids(key, result, context, :persistent_term)
        end
      _ -> true
    end
  end
  #^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

  defp delete_and_get_waiter_pids(key, :ets) do
    runner_pid = self()
    [{^key, {:running, ^runner_pid, waiter_pids}} = expected] = :ets.lookup(tab(key), key)

    if compare_and_swap(key, expected, :nothing, :ets) do
      waiter_pids
    else
      # retry
      delete_and_get_waiter_pids(key, :ets)
    end
  end

  #-----------------------persistent_term--------------------
  defp delete_and_get_waiter_pids(key, :persistent_term) do
    runner_pid = self()

    :persistent_term.get(key, [])
    |> case do
      {:running, ^runner_pid, waiter_pids} = expected ->
        if compare_and_swap(key, expected, :nothing, :persistent_term) do
          waiter_pids
        else
          # retry
          delete_and_get_waiter_pids(key, :persistent_term)
        end
      _ -> true
      end
  end
  #^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

  @map_type :memoize_map_type

  # :ets.select_replace/2 does not accept map type.
  # So normalize_key/1 convert map type to list type recursively.
  defp normalize_key(map) when is_map(map) do
    kvs = map |> Map.to_list() |> Enum.sort_by(fn {key, _} -> key end)

    xs =
      for {key, value} <- kvs do
        {normalize_key(key), normalize_key(value)}
      end

    [@map_type | xs]
  end

  defp normalize_key(key) when is_list(key) do
    for x <- key do
      normalize_key(x)
    end
  end

  defp normalize_key({}), do: {}
  # tuple optimization
  defp normalize_key({a}), do: {normalize_key(a)}
  defp normalize_key({a, b}), do: {normalize_key(a), normalize_key(b)}
  defp normalize_key({a, b, c}), do: {normalize_key(a), normalize_key(b), normalize_key(c)}

  defp normalize_key({a, b, c, d}),
    do: {normalize_key(a), normalize_key(b), normalize_key(c), normalize_key(d)}

  defp normalize_key(key) when is_tuple(key) do
    size = tuple_size(key)

    Enum.reduce(0..(size - 1), key, fn n, key ->
      value = elem(key, n)
      put_elem(key, n, normalize_key(value))
    end)
  end

  defp normalize_key(key) do
    key
  end

  def get_or_run(key, fun, opts \\ []) do
    key = normalize_key(key)
    do_get_or_run(key, fun, opts, opts |> Keyword.get(:back_end, :ets))
  end

  defp do_get_or_run(key, fun, opts, :ets) do
    key = normalize_key(key)

    case :ets.lookup(tab(key), key) do
      # not started
      [] ->
        # calc
        runner_pid = self()

        if compare_and_swap(key, :nothing, {key, {:running, runner_pid, []}}, :ets) do
          try do
            fun.()
          else
            result ->
              context = cache_strategy().cache(key, result, opts)
              waiter_pids = set_result_and_get_waiter_pids(key, result, context, :ets)

              Enum.map(waiter_pids, fn pid ->
                send(pid, {self(), :completed})
              end)

              do_get_or_run(key, fun, opts, :ets)
          catch
            kind, error ->
              # the status should be :running
              waiter_pids = delete_and_get_waiter_pids(key, :ets)

              Enum.map(waiter_pids, fn pid ->
                send(pid, {self(), :failed})
              end)

              error = Exception.normalize(kind, error)

              if Exception.exception?(error) do
                reraise error, __STACKTRACE__
              else
                apply(:erlang, kind, [error])
              end
          end
        else
          do_get_or_run(key, fun, opts, :ets)
        end

      # running
      [{^key, {:running, runner_pid, waiter_pids}} = expected] ->
        max_waiters = Memoize.Config.opts().max_waiters
        max_waiters = if(max_waiters <= 0, do: 1, else: max_waiters)
        waiters = length(waiter_pids)

        if waiters < max_waiters do
          waiter_pids = [self() | waiter_pids]

          if compare_and_swap(key, expected, {key, {:running, runner_pid, waiter_pids}}, :ets) do
            ref = Process.monitor(runner_pid)

            receive do
              {^runner_pid, :completed} ->
                :ok

              {^runner_pid, :failed} ->
                :ok

              {:DOWN, ^ref, :process, ^runner_pid, _reason} ->
                # in case the running process isn't alive anymore,
                # it means it crashed and failed to complete
                compare_and_swap(key, {key, {:running, runner_pid, waiter_pids}}, :nothing, :ets)

                Enum.map(waiter_pids, fn pid ->
                  send(pid, {self(), :failed})
                end)

                :ok
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
          end
        else
          waiter_sleep_ms = Memoize.Config.opts().waiter_sleep_ms
          Process.sleep(waiter_sleep_ms)
        end

        do_get_or_run(key, fun, opts, :ets)

      # completed
      [{^key, {:completed, value, context}}] ->
        case cache_strategy().read(key, value, context) do
          :retry -> do_get_or_run(key, fun, opts, :ets)
          :ok -> value
        end
    end
  end

  #--------------------------persistent_term---------------------------------------------
  defp do_get_or_run(key, fun, opts, :persistent_term) do
    key = normalize_key(key)

    case :persistent_term.get(key, []) do
      # not started
      [] ->
        # calc
        runner_pid = self()

        if compare_and_swap(key, :nothing, {key, {:running, runner_pid, []}}, :persistent_term) do
          try do
            fun.()
          else
            result ->
              context = cache_strategy().cache(key, result, opts)
              waiter_pids = set_result_and_get_waiter_pids(key, result, context, :persistent_term)

              Enum.map(waiter_pids, fn pid ->
                send(pid, {self(), :completed})
              end)

              do_get_or_run(key, fun, opts, :persistent_term)
          catch
            kind, error ->
              # the status should be :running
              waiter_pids = delete_and_get_waiter_pids(key, :persistent_term)

              Enum.map(waiter_pids, fn pid ->
                send(pid, {self(), :failed})
              end)

              error = Exception.normalize(kind, error)

              if Exception.exception?(error) do
                reraise error, __STACKTRACE__
              else
                apply(:erlang, kind, [error])
              end
          end
        else
          do_get_or_run(key, fun, opts, :persistent_term)
        end

      # running
      {^key, {:running, runner_pid, waiter_pids}} = expected ->
        max_waiters = Memoize.Config.opts().max_waiters
        max_waiters = if(max_waiters <= 0, do: 1, else: max_waiters)
        waiters = length(waiter_pids)

        if waiters < max_waiters do
          waiter_pids = [self() | waiter_pids]

          if compare_and_swap(key, expected, {key, {:running, runner_pid, waiter_pids}}, :persistent_term) do
            ref = Process.monitor(runner_pid)

            receive do
              {^runner_pid, :completed} ->
                :ok

              {^runner_pid, :failed} ->
                :ok

              {:DOWN, ^ref, :process, ^runner_pid, _reason} ->
                # in case the running process isn't alive anymore,
                # it means it crashed and failed to complete
                compare_and_swap(key, {key, {:running, runner_pid, waiter_pids}}, :nothing, :persistent_term)

                Enum.map(waiter_pids, fn pid ->
                  send(pid, {self(), :failed})
                end)

                :ok
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
          end
        else
          waiter_sleep_ms = Memoize.Config.opts().waiter_sleep_ms
          Process.sleep(waiter_sleep_ms)
        end

        do_get_or_run(key, fun, opts, :persistent_term)

      # completed
      {^key, {:completed, value, context}} ->
        case cache_strategy().read(key, value, context) do
          :retry -> do_get_or_run(key, fun, opts, :persistent_term)
          :ok -> value
        end
    end
  end
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

  def invalidate() do
    cache_strategy().invalidate()
  end

  def invalidate(key) do
    key = normalize_key(key)
    cache_strategy().invalidate(key)
  end

  def garbage_collect() do
    cache_strategy().garbage_collect()
  end
end
