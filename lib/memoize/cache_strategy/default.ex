if Memoize.CacheStrategy.configured?(Memoize.CacheStrategy.Default) do
  defmodule Memoize.CacheStrategy.Default do
    @moduledoc false

    @behaviour Memoize.CacheStrategy

    @ets_tab __MODULE__

    def init() do
      :ets.new(@ets_tab, [:public, :set, :named_table, {:read_concurrency, true}])
    end

    def tab(_key) do
      @ets_tab
    end

    def cache(_key, _value, opts) do
      expires_in = Keyword.get(opts, :expires_in, :infinity)
      expired_at = case expires_in do
                     :infinity -> :infinity
                     value -> System.monotonic_time(:millisecond) + value
                   end
      expired_at
    end

    def read(key, _value, expired_at) do
      if expired_at != :infinity && System.monotonic_time(:millisecond) > expired_at do
        invalidate(key)
        :retry
      else
        :ok
      end
    end

    def invalidate() do
      :ets.select_delete(@ets_tab, [{{:_, {:completed, :_, :_}}, [], [true]}])
    end

    def invalidate(key) do
      :ets.select_delete(@ets_tab, [{{key, {:completed, :_, :_}}, [], [true]}])
    end

    def garbage_collect() do
      expired_at = System.monotonic_time(:millisecond)
      :ets.select_delete(@ets_tab, [{{:_, {:completed, :_, :"$1"}}, [{:andalso, {:"/=", :"$1", :infinity}, {:<, :"$1", {:const, expired_at}}}], [true]}])
    end
  end
end
