if Memoize.CacheStrategy.configured?(Memoize.CacheStrategy.Eviction) do
  defmodule Memoize.CacheStrategy.Eviction do
    @behaviour Memoize.CacheStrategy

    @ets_tab __MODULE__
    @read_history_tab Module.concat(__MODULE__, "ReadHistory")
    @expiration_tab Module.concat(__MODULE__, "Expiration")

    @opts Application.fetch_env!(:memoize, __MODULE__)
    @max_threshold Keyword.fetch!(@opts, :max_threshold)
    if @max_threshold != :infinity do
      @min_threshold Keyword.fetch!(@opts, :min_threshold)
    end

    def init(opts) do
      case Keyword.get(opts, :caches) do
        nil ->
          :ets.new(tab(nil), [:public, :set, :named_table, {:read_concurrency, true}])
          :ets.new(history_tab(nil), [:public, :set, :named_table, {:write_concurrency, true}])
          :ets.new(expiration_tab(nil), [:public, :ordered_set, :named_table])

        caches ->
          Enum.each(caches, fn cache ->
            :ets.new(tab(cache), [:public, :set, :named_table, {:read_concurrency, true}])

            :ets.new(history_tab(cache), [:public, :set, :named_table, {:write_concurrency, true}])

            :ets.new(expiration_tab(cache), [:public, :ordered_set, :named_table])
          end)
      end
    end

    defp history_tab(cache) do
      Module.concat(tab(cache), ReadHistory)
    end

    defp expiration_tab(cache) do
      Module.concat(tab(cache), Expiration)
    end

    def tab(_module, _key \\ nil)

    def tab(nil, _key) do
      @ets_tab
    end

    def tab(module, _key) do
      Module.concat(@ets_tab, module)
    end

    def used_bytes(cache) do
      words = 0
      words = words + :ets.info(tab(cache), :memory)
      words = words + :ets.info(history_tab(cache), :memory)

      words * :erlang.system_info(:wordsize)
    end

    if @max_threshold == :infinity do
      def cache(cache, key, value, opts) do
        do_cache(cache, key, value, opts)
      end
    else
      def cache(cache, key, value, opts) do
        if used_bytes(cache) > @max_threshold do
          garbage_collect(cache)
        end

        do_cache(cache, key, value, opts)
      end
    end

    defp do_cache(cache, key, _value, opts) do
      case Keyword.fetch(opts, :expires_in) do
        {:ok, expires_in} ->
          expired_at = System.monotonic_time(:millisecond) + expires_in
          counter = System.unique_integer()
          :ets.insert(expiration_tab(cache), {{expired_at, counter}, key})

        :error ->
          :ok
      end

      %{permanent: Keyword.get(opts, :permanent, false)}
    end

    def read(cache, key, _value, context) do
      expired? = clear_expired_cache(cache, key)

      unless context.permanent do
        counter = System.unique_integer([:monotonic, :positive])
        :ets.insert(history_tab(cache), {key, counter})
      end

      if expired?, do: :retry, else: :ok
    end

    def invalidate() do
      case Application.get_env(:memoize, :caches) do
        nil ->
          num_deleted = :ets.select_delete(tab(nil), [{{:_, {:completed, :_, :_}}, [], [true]}])
          :ets.delete_all_objects(history_tab(nil))
          num_deleted

        modules ->
          Enum.reduce(modules, 0, fn module, acc ->
            num_deleted =
              :ets.select_delete(tab(module), [{{:_, {:completed, :_, :_}}, [], [true]}]) + acc

            :ets.delete_all_objects(history_tab(module))
            num_deleted
          end)
      end
    end

    def invalidate(module) do
      cache_name = Cache.cache_name(module)

      num_deleted =
        cache_name
        |> tab()
        |> :ets.select_delete([{{key(cache_name, module), {:completed, :_, :_}}, [], [true]}])

      :ets.select_delete(history_tab(cache_name), [{key(cache_name, module), [], [true]}])
      num_deleted
    end

    def invalidate(module, function) do
      cache_name = Cache.cache_name(module)

      num_deleted =
        cache_name
        |> tab()
        |> :ets.select_delete([
          {{key(cache_name, module, function), {:completed, :_, :_}}, [], [true]}
        ])

      :ets.select_delete(history_tab(cache_name), [
        {key(cache_name, module, function), [], [true]}
      ])

      num_deleted
    end

    def invalidate(module, function, args) do
      cache_name = Cache.cache_name(module)

      num_deleted =
        cache_name
        |> tab()
        |> :ets.select_delete([
          {{key(cache_name, module, function, args), {:completed, :_, :_}}, [], [true]}
        ])

      :ets.select_delete(history_tab(cache_name), [
        {key(cache_name, module, function, args), [], [true]}
      ])

      num_deleted
    end

    def garbage_collect() do
      do_garbage_collect_all(@max_threshold)
    end

    def garbage_collect(module) do
      do_garbage_collect(@max_threshold, module)
    end

    def do_garbage_collect(:infinity, _) do
      0
    end

    def do_garbage_collect(_, module) do
      cache = Cache.cache_name(module)

      if used_bytes(cache) <= @min_threshold do
        # still don't collect
        0
      else
        # remove values ordered by last accessed time until used bytes less than @min_threshold.
        values = :lists.keysort(2, :ets.tab2list(history_tab(cache)))
        stream = values |> Stream.filter(fn n -> n != :permanent end) |> Stream.with_index(1)

        try do
          for {{key, _}, num_deleted} <- stream do
            case is_our_key?(key, module) do
              true ->
                :ets.select_delete(tab(cache), [{{key, {:completed, :_, :_}}, [], [true]}])
                :ets.delete(history_tab(cache), key)

              false ->
                0
            end

            if used_bytes(cache) <= @min_threshold do
              throw({:break, num_deleted})
            end
          end
        else
          _ -> length(values)
        catch
          {:break, num_deleted} -> num_deleted
        end
      end
    end

    defp is_our_key?({_, _}, _), do: true
    defp is_our_key?({module, _, _}, module), do: true
    defp is_our_key?(_, _), do: false

    def do_garbage_collect_all(:infinity) do
      0
    end

    def do_garbage_collect_all(_) do
      Application.get_env(:memoize, :caches, [nil])
      |> Enum.reduce(0, fn cache, acc ->
        if used_bytes(cache) <= @min_threshold do
          # still don't collect
          0 + acc
        else
          # remove values ordered by last accessed time until used bytes less than @min_threshold.
          values = :lists.keysort(2, :ets.tab2list(history_tab(cache)))
          stream = values |> Stream.filter(fn n -> n != :permanent end) |> Stream.with_index(1)

          try do
            for {{key, _}, num_deleted} <- stream do
              :ets.select_delete(tab(cache), [{{key, {:completed, :_, :_}}, [], [true]}])
              :ets.delete(history_tab(cache), key)

              if used_bytes(cache) <= @min_threshold do
                throw({:break, num_deleted})
              end
            end
          else
            _ -> length(values) + acc
          catch
            {:break, num_deleted} -> num_deleted + acc
          end
        end
      end)
    end

    def clear_expired_cache(cache, read_key \\ nil, expired? \\ false) do
      case :ets.first(expiration_tab(cache)) do
        :"$end_of_table" ->
          expired?

        {expired_at, _counter} = key ->
          case :ets.lookup(expiration_tab(cache), key) do
            [] ->
              # retry
              clear_expired_cache(cache, read_key, expired?)

            [{^key, cache_key}] ->
              now = System.monotonic_time(:millisecond)

              if now > expired_at do
                invalidate(cache_key)
                :ets.delete(expiration_tab(cache), key)
                expired? = expired? || cache_key == read_key
                # next
                clear_expired_cache(cache, read_key, expired?)
              else
                # completed
                expired?
              end
          end
      end
    end

    # ets per module
    defp key(module_name, module_name) do
      {:_, :_}
    end

    defp key(_cache_name, module_name) do
      {module_name, :_, :_}
    end

    # ets per module
    defp key(module_name, module_name, function_name) do
      {function_name, :_}
    end

    defp key(_cache_name, module_name, function_name) do
      {module_name, function_name, :_}
    end

    # ets per module
    defp key(module_name, module_name, function_name, args) do
      {function_name, args}
    end

    defp key(_cache_name, module_name, function_name, args) do
      {module_name, function_name, args}
    end
  end
end
