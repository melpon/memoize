# Changelog

## 1.3.1

- require Elixir >= 1.9
- Fix warnings for Elixir 1.11
- Fix freeze when exit or throw ([#13](https://github.com/melpon/memoize/issues/13))
- Update dependencies

## 1.3.0

- Limit count of waiter processes that receive message passing.
- Update dependencies

## 1.2.8

- Fix `defmemo unquote(name)()` doesn't work

## 1.2.7

- Update dependencies

## 1.2.6

- Apply elixir formatter

## 1.2.5

- Update a dependency `ex_doc`
- Improve documents

## 1.2.4

- Fix map type is passed to `:ets.select_replace/2`
- Improve documents

## 1.2.3

- Fix passing map type to `:ets.select_replace/2`
