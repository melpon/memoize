alias Memoize.Benchmarks.Bench

children = [
  {Cachex, name: :my_cache}
]

opts = [strategy: :one_for_one, name: Bench.Supervisor]
Supervisor.start_link(children, opts)

Benchee.run(
  %{
    "memoize" => fn input -> Bench.run(Memoize.Benchmarks.Memoize, input) end,
    "cachex" => fn input -> Bench.run(Memoize.Benchmarks.Cachex, input) end
  },
  inputs: %{
    # number of times per process
    # number of processes
    # number range for cached values

    "write" => {1, 10_000, 100_000_000_000},
    "read" => {100, 10_000, 1},
    # "medium" => {100, 10_000, 100},
    # "large" => {1_000, 10_000, 100}
  },
  time: 10,
  memory_time: 2,
  before_scenario: fn input -> Bench.before_scenario(input) end,
  after_scenario: fn input -> Bench.after_scenario(input) end,
  formatters: [
    {Benchee.Formatters.HTML, file: "benchmarks/html/bench.html", auto_open: false},
    Benchee.Formatters.Console
  ]
)
