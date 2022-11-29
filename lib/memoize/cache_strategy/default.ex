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
      Application.get_env(:memoize, __MODULE__, []) |> Keyword.get(:expires_in, 5000)

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
        :infinity -> :infinity
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
    :persistent_term.get()
    |> Enum.each(fn {key, value} ->
      value
      |> case do
        {{Memoize.Cache, _, _}, {:completed, _, _}} ->
          :persistent_term.erase(key)
        _ ->
          true
      end
    end)

    :ets.select_delete(@ets_tab, [{{:_, {:completed, :_, :_}}, [], [true]}])
  end

  def invalidate(key) do
    :persistent_term.get(key, [])
    |> case do
      [] ->
        :ets.select_delete(@ets_tab, [{{:_, {:completed, :_, :_}}, [], [true]}])
      _ ->
        :persistent_term.erase(key)
    end
  end

  def garbage_collect() do
    expired_at = System.monotonic_time(:millisecond)

    :persistent_term.get()
    |> Enum.each(fn {key, value} ->
      value
      |> case do
        {{Memoize.CacheStrategy.Default, _, _}, {:completed, _, to_be_expired}} ->
          cond do
            to_be_expired |> is_number() and to_be_expired < expired_at ->
              :persistent_term.erase(key)
            true ->
              true
          end

        _ ->
          true
      end
    end)

    :ets.select_delete(@ets_tab, [
      {{:_, {:completed, :_, :"$1"}},
       [{:andalso, {:"/=", :"$1", :infinity}, {:<, :"$1", {:const, expired_at}}}], [true]}
    ])
  end
end
