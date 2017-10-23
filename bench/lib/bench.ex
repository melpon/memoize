defmodule Bench do
  def calc(n) do
    Process.sleep(100)
    :ets.update_counter(:counter, n, 1, {n, 0})
  end

  @process_count 10_000
  @func_count 100

  defp gen_processes(n) do
    for v <- 1..n do
      {:ok, pid} = Agent.start_link(fn -> v end)
      pid
    end
  end

  defp receive_all(xs) do
    receive do
      v ->
        xs = [v | xs]
        if length(xs) == @process_count do
          xs
        else
          receive_all(xs)
        end
    after
      30_000 ->
        raise "#{length(xs)}, #{inspect(Enum.sort(xs))}"
    end
  end

  def run(module, count) do
    :ets.new(:counter, [:set, :named_table, :public])

    pids = gen_processes(@process_count)
    from = self()
    start_at = System.monotonic_time(:millisecond)
    for pid <- pids do
      Agent.cast(pid, fn v ->
        for _ <- 1..count do
          n = :rand.uniform(@func_count)
          module.test(n)
        end
        send(from, v)
      end)
    end
    receive_all([])
    time = System.monotonic_time(:millisecond) - start_at
    IO.puts "#{module} (#{count}) -> #{time} ms"
    if module == Bench.Memoize do
      IO.puts "  cache strategy: #{Memoize.cache_strategy()}"
    end

    for n <- 1..@func_count do
      case :ets.lookup(:counter, n) do
        [] -> IO.puts "#{n}: not called"
        [{_, v}] ->
          if v != 1 do
            IO.puts "#{n}: #{v} times called"
          end
      end
    end
  end
end
