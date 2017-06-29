defmodule Memoize.Application do
  @behaviour Application
  @behaviour Supervisor

  @ets_tab __MODULE__

  def start(_type, _args) do
    Supervisor.start_link(__MODULE__, [], strategy: :one_for_one)
  end

  def stop(_state) do
    :ok
  end

  def init(_) do
    :ets.new(@ets_tab, [:public, :set, :named_table])
    Supervisor.Spec.supervise([], strategy: :one_for_one)
  end

  def tab() do
    @ets_tab
  end
end
