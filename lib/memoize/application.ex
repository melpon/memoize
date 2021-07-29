defmodule Memoize.Application do
  @moduledoc false

  @behaviour Application
  @behaviour Supervisor

  def start(_type, args) do
    Supervisor.start_link(__MODULE__, args, strategy: :one_for_one)
  end

  def stop(_state) do
    :ok
  end

  def init(args) do
    Memoize.Config.init(args)
    Supervisor.init([], strategy: :one_for_one)
  end

  @deprecated "Use Memoize.Config.cache_strategy/0 instead"
  def cache_strategy() do
    Memoize.Config.cache_strategy()
  end
end
