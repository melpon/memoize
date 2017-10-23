#!/bin/bash

function run() {
  rm -r _build/test/lib/memoize
  rm -r _build/test/lib/bench
  MIX_ENV=test mix test
}

BENCH_CONFIG=memoize.default  BENCH_COUNT=1   run
BENCH_CONFIG=memoize.default  BENCH_COUNT=100 run
BENCH_CONFIG=memoize.eviction BENCH_COUNT=1   run
BENCH_CONFIG=memoize.eviction BENCH_COUNT=100 run
BENCH_CONFIG=defmemo          BENCH_COUNT=1   run
BENCH_CONFIG=defmemo          BENCH_COUNT=100 run
BENCH_CONFIG=cachex           BENCH_COUNT=1   run
BENCH_CONFIG=cachex           BENCH_COUNT=100 run
