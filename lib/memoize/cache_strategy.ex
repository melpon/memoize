defmodule Memoize.CacheStrategy do
  @callback init(Keyword.t()) :: any
  @callback tab(atom, any) :: atom
  @callback cache(atom, any, any, Keyword.t()) :: any
  @callback read(atom, any, any, any) :: :ok | :retry
  @callback invalidate() :: integer
  @callback invalidate(atom) :: integer
  @callback invalidate(atom, atom) :: integer
  @callback invalidate(atom, atom, any) :: integer
  @callback garbage_collect() :: integer
  @callback garbage_collect(atom) :: integer

  def configured?(mod) do
    Application.get_env(:memoize, :cache_strategy, Memoize.CacheStrategy.Default) == mod
  end
end
