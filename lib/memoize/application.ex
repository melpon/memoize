defmodule Memoize.Application do
  @moduledoc false

  @behaviour Application
  @behaviour Supervisor

  @memory_strategy Application.get_env(:memoize, :memory_strategy, Memoize.MemoryStrategy.Default)

  def start(_type, _args) do
    Supervisor.start_link(__MODULE__, [], strategy: :one_for_one)
  end

  def stop(_state) do
    :ok
  end

  def init(_) do
    @memory_strategy.init()
    Supervisor.Spec.supervise([], strategy: :one_for_one)
  end
end
