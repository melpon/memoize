defmodule Bench.Application do
  use Application

  def start(_type, _args) do
    children = [
      Supervisor.Spec.worker(Cachex, [:my_cache, [transactions: true], []]),
    ]

    opts = [strategy: :one_for_one, name: Bench.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
