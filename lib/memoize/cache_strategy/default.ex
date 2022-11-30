defmodule Memoize.CacheStrategy.Default do
  @moduledoc false

  @behaviour Memoize.CacheStrategy

  @ets_tab __MODULE__

  def init(opts) do
    :ets.new(@ets_tab, [:public, :set, :named_table, {:read_concurrency, true}])

    # Default global settings
    #
    # config :memoize, Memoize.CacheStrategy.Default,
    #   expires_in: 1000
    expires_in =
      Application.get_env(:memoize, __MODULE__, []) |> Keyword.get(:expires_in, :infinity)

    opts = Keyword.put(opts, :expires_in, expires_in)
    opts
  end

  def tab(_key) do
    @ets_tab
  end

  def cache(_key, _value, opts) do
    expires_in = Keyword.get(opts, :expires_in, Memoize.Config.opts().expires_in)

    expired_at =
      case expires_in do
        :infinity ->
          :infinity

        value ->
          System.monotonic_time(:millisecond) + value
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
    persistent_terms =
      :ets.select(@ets_tab, [{{:"$1", {:completed, :_, :_}, :persistent_term}, [], [:"$1"]}])
      |> Enum.reduce(0, fn key, acc ->
        key
        |> :persistent_term.erase()
        |> case do
          true ->
            acc + 1
          _ ->
            acc
        end
      end)

    persistent_term_keys_ets = :ets.select_delete(@ets_tab, [{{:_, {:completed, :_, :_}, :persistent_term}, [], [true]}])

    :ets.select_delete(@ets_tab, [{{:_, {:completed, :_, :_}}, [], [true]}])
    |> Kernel.+(persistent_terms + persistent_term_keys_ets)
  end

  def invalidate(key) do
    :persistent_term.get(key, [])
    |> case do
      [] ->
        :ets.select_delete(@ets_tab, [{{key, {:completed, :_, :_}}, [], [true]}])

      _ ->
        :ets.select_delete(@ets_tab, [{{key, {:completed, :_, :_}, :persistent_term}, [], [true]}])
        |> Kernel.+(
          :persistent_term.erase(key)
          |> case do
            true ->
              1
            _ ->
              0
          end
        )
    end
  end

  def garbage_collect() do
    expired_at = System.monotonic_time(:millisecond)

    persistent_terms =
      :ets.select(@ets_tab, [
        {{:"$1", {:completed, :_, :"$2"}, :persistent_term},
         [{:andalso, {:"/=", :"$2", :infinity}, {:<, :"$2", {:const, expired_at}}}], [:"$1"]}
      ])
      |> Enum.reduce(0, fn key, acc ->
        key
        |> :persistent_term.erase()
        |> case do
          true ->
            acc + 1
          _ ->
            acc
        end
      end)

    persistent_term_keys_ets =
      :ets.select_delete(@ets_tab, [
        {{:_, {:completed, :_, :"$1"}, :persistent_term},
         [{:andalso, {:"/=", :"$1", :infinity}, {:<, :"$1", {:const, expired_at}}}], [true]}
      ])

    :ets.select_delete(@ets_tab, [
      {{:_, {:completed, :_, :"$1"}},
       [{:andalso, {:"/=", :"$1", :infinity}, {:<, :"$1", {:const, expired_at}}}], [true]}
    ])
    |> Kernel.+(persistent_terms + persistent_term_keys_ets)
  end
end
