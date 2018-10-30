#!/bin/bash

set -ex

export MEMOIZE_TEST_MODE="Memoize.CacheStrategy.Default"
cp config/default_config.exs config/config.exs
mix test

export MEMOIZE_TEST_MODE="Memoize.CacheStrategy.Eviction"
cp config/eviction_config.exs config/config.exs
mix test

export MEMOIZE_TEST_MODE="Memoize.CacheStrategy.Eviction_2"
cp config/eviction_config_2.exs config/config.exs
mix test

export MEMOIZE_TEST_MODE="Memoize.WaiterConfig"
cp config/waiter_config.exs config/config.exs
mix test

rm config/config.exs
