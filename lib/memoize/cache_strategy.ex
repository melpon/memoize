defmodule Memoize.CacheStrategy do
  @moduledoc """
  A behaviour module for implementing cache strategy.
  """

  # TODO: remove 2.0
  @callback init() :: any

  @callback init(Keyword.t()) :: Keyword.t()
  @callback tab(any) :: atom
  @callback cache(any, any, Keyword.t()) :: any
  @callback read(any, any, any) :: :ok | :retry
  @callback invalidate() :: integer
  @callback invalidate(any) :: integer
  @callback garbage_collect() :: integer

  # TODO: remove 2.0
  def configured?(mod) do
    Application.get_env(:memoize, :cache_strategy, Memoize.CacheStrategy.Default) == mod
  end

  @optional_callbacks init: 0, init: 1
end
