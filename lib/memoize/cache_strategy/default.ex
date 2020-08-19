if Memoize.CacheStrategy.configured?(Memoize.CacheStrategy.Default) do
  defmodule Memoize.CacheStrategy.Default do
    @moduledoc false

    @behaviour Memoize.CacheStrategy

    @default_expires_in Application.get_env(:memoize, :expires_in, :infinity)

    @ets_tab __MODULE__
    alias Memoize.Cache

    def init(opts) do
      case Keyword.get(opts, :caches) do
        nil ->
          :ets.new(tab(nil), [:public, :set, :named_table, {:read_concurrency, true}])

        caches ->
          Enum.each(caches, fn cache ->
            :ets.new(tab(cache), [:public, :set, :named_table, {:read_concurrency, true}])
          end)
      end
    end

    def tab(_module, _key \\ nil)

    def tab(nil, _key) do
      @ets_tab
    end

    def tab(module, _key) do
      Module.concat(@ets_tab, module)
    end

    def cache(_module, _key, _value, opts) do
      expires_in = Keyword.get(opts, :expires_in, @default_expires_in)

      expired_at =
        case expires_in do
          :infinity -> :infinity
          value -> System.monotonic_time(:millisecond) + value
        end

      expired_at
    end

    def read(cache_name, key, _value, expired_at) do
      if expired_at != :infinity && System.monotonic_time(:millisecond) > expired_at do
        local_invalidate(cache_name, key)
        :retry
      else
        :ok
      end
    end

    defp local_invalidate(cache_name, key) do
      :ets.select_delete(tab(cache_name), [{{key, {:completed, :_, :_}}, [], [true]}])
    end

    def invalidate() do
      # this is only place we have to run get_env, but given we are deleting everything its fine.
      Application.get_env(:memoize, :caches, [nil])
      |> Enum.reduce(0, fn cache, acc ->
        :ets.select_delete(tab(cache), [{{:_, {:completed, :_, :_}}, [], [true]}]) + acc
      end)
    end

    def invalidate(module) do
      cache_name = Cache.cache_name(module)

      cache_name
      |> tab()
      |> :ets.select_delete([{{key(cache_name, module), {:completed, :_, :_}}, [], [true]}])
    end

    def invalidate(module, function) do
      cache_name = Cache.cache_name(module)

      cache_name
      |> tab()
      |> :ets.select_delete([
        {{key(cache_name, module, function), {:completed, :_, :_}}, [], [true]}
      ])
    end

    def invalidate(module, function, args) do
      cache_name = Cache.cache_name(module)

      cache_name
      |> tab()
      |> :ets.select_delete([
        {{key(cache_name, module, function, args), {:completed, :_, :_}}, [], [true]}
      ])
    end

    def garbage_collect() do
      expired_at = System.monotonic_time(:millisecond)
      # this is only place we have to run get_env, but given we are deleting everything its fine.
      Application.get_env(:memoize, :caches, [nil])
      |> Enum.reduce(0, fn cache, acc ->
        :ets.select_delete(tab(cache), [
          {{:_, {:completed, :_, :"$1"}},
           [{:andalso, {:"/=", :"$1", :infinity}, {:<, :"$1", {:const, expired_at}}}], [true]}
        ]) + acc
      end)
    end

    def garbage_collect(module) do
      expired_at = System.monotonic_time(:millisecond)

      cache_name = Cache.cache_name(module)

      cache_name
      |> tab()
      |> :ets.select_delete([
        {{key(cache_name, module), {:completed, :_, :"$1"}},
         [{:andalso, {:"/=", :"$1", :infinity}, {:<, :"$1", {:const, expired_at}}}], [true]}
      ])
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
