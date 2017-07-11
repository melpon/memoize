defmodule Memoize.MemoryStrategy.Eviction do
  @behaviour Memoize.MemoryStrategy

  @ets_tab __MODULE__
  @read_history_tab Module.concat(__MODULE__, "ReadHistory")
  @opts (if Application.get_env(:memoize, :memory_strategy) == __MODULE__ do
           Application.get_env(:memoize, __MODULE__)
         else
           []
         end)
  @max_threshold Keyword.get(@opts, :max_threshold)
  @min_threshold Keyword.get(@opts, :min_threshold)

  def init() do
    :ets.new(@ets_tab, [:public, :set, :named_table, {:read_concurrency, true}])
    :ets.new(@read_history_tab, [:public, :set, :named_table, {:write_concurrency, true}])
  end

  def tab(_key) do
    @ets_tab
  end

  defp used_bytes() do
    words = :ets.info(@ets_tab, :memory)
    words * :erlang.system_info(:wordsize)
  end

  def cache(key, _value, _opts) do
    if used_bytes() > @max_threshold do
      garbage_collect()
    end

    counter = System.unique_integer([:monotonic, :positive])
    :ets.insert(@read_history_tab, {key, counter})
    nil
  end

  def read(key, _value, _expired_at) do
    counter = System.unique_integer([:monotonic, :positive])
    :ets.update_element(@read_history_tab, key, {2, counter})
    :ok
  end

  def invalidate() do
    :ets.select_delete(@ets_tab, [{{:_, {:completed, :_, :_}}, [], [true]}])
  end

  def invalidate(_key) do
    0
  end

  def garbage_collect() do
    if used_bytes() > @min_threshold do
      # remove values ordered by last accessed time until used bytes less than @min_threshold.
      values = :lists.keysort(2, :ets.tab2list(@read_history_tab))
      try do
        for {key, _} <- values do
          :ets.select_delete(@ets_tab, [{{key, {:completed, :_, :_}}, [], [true]}])
          :ets.delete(@read_history_tab, key)

          if used_bytes() <= @min_threshold do
            throw :break
          end
        end
      catch
        :break -> :ok
      end
    end
    :ok
  end
end
