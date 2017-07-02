# Memoize

A memoization macro.

## Requirement

- Elixir 1.4.5 or later.
- Erlang/OTP 20 or later.

## Installation

Add `:memoize` to your `mix.exs` dependencies:

```
defp deps do
  [{:memoize, "~> 1.0.0"}]
end
```

## How to memoize

If you want to cache a function, `use Memoize` on the module and change `def` to `defmemo`.

for example:

```elixir
defmodule Fib do
  def fibs(0), do: 0
  def fibs(1), do: 1
  def fibs(n), do: fibs(n - 1) + fibs(n - 2)
end
```

this code changes to:

```elixir
defmodule Fib do
  use Memoize
  defmemo fibs(0), do: 0
  defmemo fibs(1), do: 1
  defmemo fibs(n), do: fibs(n - 1) + fibs(n - 2)
end
```

## Exclusive

A caching function that is defined by `defmemo` is never called in parallel.

```elixir
defmodule Calc do
  use Memoize
  defmemo calc() do
    Process.sleep(1000)
    IO.puts "called!"
  end
end

# call `Calc.calc/0` in parallel using many processes.
for _ <- 1..10000 do
  Process.spawn(fn -> Calc.calc() end, [])
end

# but, actually `Calc.calc/0` is called only once.
```

## Expiration

If you want to invalidate the cache after a certain period of time, you can use `:expired_in`.

```elixir
defmodule Api do
  use Memoize
  defmemo get_config(), expires_in: 60 * 1000 do
    call_external_api()
  end
end
```

The cached value is invalidated in the first `get_config/0` function call after `expires_in` milliseconds have elapsed.

## Invalidate

If you want to invalidate cache, you can use `Memoize.invalidate/{0-3}`.

```elixir
# invalidate a cached value of `Fib.fibs(0)`.
Memoize.invalidate(Fib, :fibs, [0])

# invalidate all cached values of `Fib.fibs/1`.
Memoize.invalidate(Fib, :fibs)

# invalidate all cached values of `Fib` module.
Memoize.invalidate(Fib)

# invalidate all cached values.
Memoize.invalidate()
```

Notice: `Memoize.invalidate/{0-3}`'s complexity is linear. Therefore, it takes a long time if `Memoize` has many cached values.

## Internal

`Memoize` is using CAS (compare-and-swap) on ETS.

CAS is [now available](http://erlang.org/doc/man/ets.html#select_replace-2) in Erlang/OTP 20.
