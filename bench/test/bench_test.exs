defmodule BenchTest do
  use ExUnit.Case
  doctest Bench

  test "test" do
    module = Application.fetch_env!(:bench, :module)
    count = Application.fetch_env!(:bench, :count)
    Bench.run(module, count)
  end
end
