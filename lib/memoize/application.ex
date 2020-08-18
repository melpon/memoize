defmodule Memoize.Application do
  @moduledoc false

  @behaviour Application
  @behaviour Supervisor

  @cache_strategy Application.get_env(:memoize, :cache_strategy, Memoize.CacheStrategy.Default)

  def start(_type, _args) do
    Supervisor.start_link(__MODULE__, [], strategy: :one_for_one, name: __MODULE__)
  end

  def stop(_state) do
    :ok
  end

  def init(_opts) do
    caches = Application.get_env(:memoize, :caches)
    @cache_strategy.init(caches: caches)
    Supervisor.Spec.supervise([], strategy: :one_for_one)
  end

  def cache_strategy() do
    @cache_strategy
  end
end
