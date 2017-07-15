defmodule Memoize.CacheStrategy do
  @callback init() :: any
  @callback tab(any) :: atom
  @callback cache(any, any, Keyword.t) :: any
  @callback read(any, any, any) :: :ok | :retry
  @callback invalidate() :: integer
  @callback invalidate(any) :: integer
  @callback garbage_collect() :: integer

  def configured?(mod) do
    Application.get_env(:memoize, :cache_strategy, Memoize.CacheStrategy.Default) == mod
  end
end
