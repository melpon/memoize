# Changelog

## develop

## 1.4.1 2022-09-04

- Update dependencies
- fix: Invalidate cache with map
    - @phanmn

## 1.4.0 2021-07-30

- Add the default value of `:expires_in` configurable.
- Remove compile-time config.

## 1.3.3 2021-02-03

- Fix infinite loop if cache process crashes ([#14](https://github.com/melpon/memoize/pull/14))
    - @davorbadrov

## 1.3.2 2020-10-09

- Replace `is_exception/1` to `Exception.exception?/1`.

## 1.3.1 2020-10-07

- Require Elixir >= 1.9
- Fix warnings for Elixir 1.11
- Fix freeze when exit or throw ([#13](https://github.com/melpon/memoize/issues/13))
- Update dependencies

## 1.3.0 2018-10-31

- Limit count of waiter processes that receive message passing
- Update dependencies

## 1.2.8 2018-07-21

- Fix `defmemo unquote(name)()` doesn't work

## 1.2.7 2018-04-16

- Update dependencies

## 1.2.6 2018-01-23

- Apply Elixir formatter

## 1.2.5 2018-01-06

- Update a dependency `ex_doc`
- Improve documents

## 1.2.4 2017-10-22

- Fix map type is passed to `:ets.select_replace/2`
- Improve documents

## 1.2.3 2017-09-28

- Fix passing map type to `:ets.select_replace/2`
