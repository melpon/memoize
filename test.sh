#!/bin/bash

set -ex

cp config/default_config.exs config/config.exs
mix test

cp config/eviction_config.exs config/config.exs
mix test

rm config/config.exs
