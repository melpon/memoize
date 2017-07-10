# Memoize

A memoization macro.

The application available in [hex.pm](https://hex.pm/packages/memoize).

## Requirement

- Elixir 1.4.5 or later.
- Erlang/OTP 20 or later.

## Installation

Add `:memoize` to your `mix.exs` dependencies:

```elixir
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

If a function defined by `defmemo` raises an error, the result is not cached and one of waiting processes will call the function.

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

To collect expired values, you can use `garbage_collect/0`. It collects all expired values. Its complexity is linear.

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

Notice: `Memoize.invalidate/{0-2}`'s complexity is linear. Therefore, it takes a long time if `Memoize` has many cached values.

## Memory Strategy

You can customize memory strategy.

```elixir
defmodule Memoize.MemoryStrategy do
  @callback init() :: any
  @callback tab(any) :: atom
  @callback cache(any, any, Keyword.t) :: any
  @callback read(any, any, any) :: :ok | :retry
  @callback invalidate() :: integer
  @callback invalidate(any) :: integer
  @callback garbage_collect() :: integer
end
```

If you want to use a customized memory strategy, implement `Memoize.MemoryStrategy` behaviour.

```elixir
defmodule YourAwesomeApp.ExcellentMemoryStrategy do
  @behaviour Memoize.MemoryStrategy

  def init() do
    ...
  end

  ...
end
```

Then, configure `:memory_strategy` in `:memoize` application.

```elixir
config :memoize,
  memory_strategy: YourAwesomeApp.ExcellentMemoryStrategy
```

WARNING: A memory strategy module is determined at *compile time*. It mean you **MUST** recompile `memoize` module when you change memory strategy.

By default, the memory strategy is `Memoize.MemoryStrategy.Default`.

### init/0

When application is started, `init/0` is called only once.

### tab/1

To determine which ETS tab to use, Memoize calls `tab/0`.

### cache/3

When new value is cached, `cache/3` will be called.
The first argument is `key` that is used as cache key.
The second argument is `value` that is calculated value by cache key.
The third argument is `opts` that is passed by `defmemo`.

`cache/3` can return an any value that is called `context`.
`context` is stored to ETS.
And then, the context is passed to `read/3`'s third argument.

### read/3

When a value is looked up by a key, `read/3` will be called.
first and second arguments are same as `cache/3`.
The third argument is `context` that is created at `cache/3`.

`read/3` can return `:retry` or `:ok`.
If `:retry` is returned, retry the lookup.
If `:ok` is returned, return the `value`.

### invalidte/{0,1}

These functions are called from `Memoize.invalidate/{0-4}`.

### garbage_collect/0

The function is called from `Memoize.garbage_collect/0`.

## Internal

`Memoize` is using CAS (compare-and-swap) on ETS.

CAS is [now available](http://erlang.org/doc/man/ets.html#select_replace-2) in Erlang/OTP 20.
