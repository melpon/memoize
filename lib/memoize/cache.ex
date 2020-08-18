defmodule Memoize.Cache do
  @cache_strategy Memoize.Application.cache_strategy()
  @max_waiters Application.get_env(:memoize, :max_waiters, 20)
  @waiter_sleep_ms Application.get_env(:memoize, :waiter_sleep_ms, 200)

  def cache_name(module) do
    if function_exported?(module, :__memoize_cache_name__, 0) do
      module.__memoize_cache_name__
    else
      nil
    end
  end

  defp tab(cache_name, key) do
    @cache_strategy.tab(cache_name, key)
  end

  defp compare_and_swap(cache_name, key, :nothing, value) do
    :ets.insert_new(tab(cache_name, key), value)
  end

  defp compare_and_swap(cache_name, key, expected, :nothing) do
    num_deleted = :ets.select_delete(tab(cache_name, key), [{expected, [], [true]}])
    num_deleted == 1
  end

  defp compare_and_swap(cache_name, key, expected, value) do
    num_replaced = :ets.select_replace(tab(cache_name, key), [{expected, [], [{:const, value}]}])
    num_replaced == 1
  end

  defp set_result_and_get_waiter_pids(cache_name, key, result, context) do
    runner_pid = self()

    [{^key, {:running, ^runner_pid, waiter_pids}} = expected] =
      :ets.lookup(tab(cache_name, key), key)

    if compare_and_swap(cache_name, key, expected, {key, {:completed, result, context}}) do
      waiter_pids
    else
      # retry
      set_result_and_get_waiter_pids(cache_name, key, result, context)
    end
  end

  defp delete_and_get_waiter_pids(cache_name, key) do
    runner_pid = self()

    [{^key, {:running, ^runner_pid, waiter_pids}} = expected] =
      :ets.lookup(tab(cache_name, key), key)

    if compare_and_swap(cache_name, key, expected, :nothing) do
      waiter_pids
    else
      # retry
      delete_and_get_waiter_pids(cache_name, key)
    end
  end

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

  def get_or_run(module, function, args, fun, opts \\ [])

  def get_or_run(module, function, args, fun, opts) when not is_function(fun) do
    get_or_run(module, function, args, fn -> fun end, opts)
  end

  def get_or_run(module, function, args, fun, opts) do
    cache_name = cache_name(module)

    key =
      case cache_name == module do
        true ->
          {function, args}

        false ->
          {module, function, args}
      end

    key = normalize_key(key)
    do_get_or_run(cache_name, key, fun, opts)
  end

  defp do_get_or_run(cache_name, key, fun, opts) do
    key = normalize_key(key)

    case :ets.lookup(tab(cache_name, key), key) do
      # not started
      [] ->
        # calc
        runner_pid = self()

        if compare_and_swap(cache_name, key, :nothing, {key, {:running, runner_pid, []}}) do
          try do
            fun.()
          else
            result ->
              context = @cache_strategy.cache(cache_name, key, result, opts)
              waiter_pids = set_result_and_get_waiter_pids(cache_name, key, result, context)

              Enum.map(waiter_pids, fn pid ->
                send(pid, {self(), :completed})
              end)

              do_get_or_run(cache_name, key, fun, opts)
          rescue
            error ->
              # the status should be :running
              waiter_pids = delete_and_get_waiter_pids(cache_name, key)

              Enum.map(waiter_pids, fn pid ->
                send(pid, {self(), :failed})
              end)

              reraise error, System.stacktrace()
          end
        else
          do_get_or_run(cache_name, key, fun, opts)
        end

      # running
      [{^key, {:running, runner_pid, waiter_pids}} = expected] ->
        max_waiters = Keyword.get(opts, :max_waiters, @max_waiters)
        waiters = length(waiter_pids)

        if waiters < max_waiters do
          waiter_pids = [self() | waiter_pids]

          if compare_and_swap(
               cache_name,
               key,
               expected,
               {key, {:running, runner_pid, waiter_pids}}
             ) do
            ref = Process.monitor(runner_pid)

            receive do
              {^runner_pid, :completed} -> :ok
              {^runner_pid, :failed} -> :ok
              {:DOWN, ^ref, :process, ^runner_pid, _reason} -> :ok
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
          waiter_sleep_ms = Keyword.get(opts, :waiter_sleep_ms, @waiter_sleep_ms)
          Process.sleep(waiter_sleep_ms)
        end

        do_get_or_run(cache_name, key, fun, opts)

      # completed
      [{^key, {:completed, value, context}}] ->
        case @cache_strategy.read(cache_name, key, value, context) do
          :retry -> do_get_or_run(cache_name, key, fun, opts)
          :ok -> value
        end
    end
  end

  def invalidate() do
    @cache_strategy.invalidate()
  end

  def invalidate(module) do
    @cache_strategy.invalidate(module)
  end

  def invalidate(module, function) do
    @cache_strategy.invalidate(module, function)
  end

  def invalidate(module, function, arguments) do
    @cache_strategy.invalidate(module, function, normalize_key(arguments))
  end

  def garbage_collect() do
    @cache_strategy.garbage_collect()
  end

  def garbage_collect(module) do
    @cache_strategy.garbage_collect(module)
  end
end
