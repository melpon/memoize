defmodule Memoize.Benchmarks.Bench do
  def before_scenario({_input_count, process_count, func_count} = input) do
    pids = gen_processes(process_count)

    counter = :counters.new(3, [])
    if func_count == 1 do
      Memoize.Benchmarks.Cachex.test(func_count, counter)
      Memoize.Benchmarks.Memoize.test(func_count, counter)
      :counters.put(counter, 1, 0)
      :counters.put(counter, 2, 0)
      :counters.put(counter, 3, 0)
    end

    {input, {pids, counter}}
  end

  def after_scenario({_input, {pids, counter}}) do
    misses = :counters.get(counter, 1)
    hits = :counters.get(counter, 2)
    IO.puts("Misses: #{misses}, Hits: #{hits-misses}")
    Enum.each(pids, fn pid -> Agent.stop(pid) end)
  end

  def calc(_n, counter) do
    :counters.add(counter, 1, 1)
  end

  defp gen_processes(process_count) do
    for v <- 1..process_count do
      {:ok, pid} = Agent.start_link(fn -> v end)
      pid
    end
  end

  def get_pid(process_count, process_count, pids, counter) do
    :counters.put(counter, 3, 0)
    get_pid(0, process_count, pids, counter)
  end

  def get_pid(count, _process_count, pids, counter) do
    :counters.add(counter, 3, 1)
    Enum.at(pids, count)
  end


  def run(module, {{input_count, process_count, func_count}, {pids, counter}}) do
    counter
    |> :counters.get(3)
    |> get_pid(process_count, pids, counter)
    |> Agent.update(
      fn _ ->
        for _ <- 1..input_count do
          n = :rand.uniform(func_count)
          module.test(n, counter)
	  :counters.add(counter, 2, 1)
        end
    end, 30_000)
  end
end
