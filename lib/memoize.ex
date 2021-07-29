defmodule Memoize do
  @moduledoc """
  Module documentation for Memoize.
  """

  defmacro __using__(_) do
    quote do
      import Memoize,
        only: [defmemo: 1, defmemo: 2, defmemo: 3, defmemop: 1, defmemop: 2, defmemop: 3]

      @memoize_memodefs []
      @memoize_origdefined %{}
      @before_compile Memoize
    end
  end

  @doc ~S"""
  Define the memoized function.

  Below code:

      defmemo foo(0, y) do
        y
      end

      defmemo foo(x, y) when x == 1 do
        y * z
      end

      defmemo foo(x, y, z \\ 0) when x == 2 do
        y * z
      end

  is converted to:

      def foo(t1, t2) do
        Memoize.Cache.get_or_run({__MODULE__, :foo, [t1, t2]}, fn -> __foo_memoize(t1, t2) end)
      end

      def foo(t1, t2, t3) do
        Memoize.Cache.get_or_run({__MODULE__, :foo, [t1, t2, t3]}, fn -> __foo_memoize(t1, t2, t3) end)
      end

      def __foo_memoize(0, y) do
        y
      end

      def __foo_memoize(x, y) when x == 1 do
        y * z
      end

      def __foo_memoize(x, y, z \\ 0) when x == 2 do
        y * z
      end

  """
  defmacro defmemo(call, expr_or_opts \\ nil) do
    {opts, expr} = resolve_expr_or_opts(expr_or_opts)
    define(:def, call, opts, expr)
  end

  defmacro defmemop(call, expr_or_opts \\ nil) do
    {opts, expr} = resolve_expr_or_opts(expr_or_opts)
    define(:defp, call, opts, expr)
  end

  defmacro defmemo(call, opts, expr) do
    define(:def, call, opts, expr)
  end

  defmacro defmemop(call, opts, expr) do
    define(:defp, call, opts, expr)
  end

  defp resolve_expr_or_opts(expr_or_opts) do
    cond do
      expr_or_opts == nil ->
        {[], nil}

      # expr_or_opts is expr
      Keyword.has_key?(expr_or_opts, :do) ->
        {[], expr_or_opts}

      # expr_or_opts is opts
      true ->
        {expr_or_opts, nil}
    end
  end

  defp define(method, call, _opts, nil) do
    # declare function
    quote do
      case unquote(method) do
        :def -> def unquote(call)
        :defp -> defp unquote(call)
      end
    end
  end

  defp define(method, call, opts, expr) do
    register_memodef =
      case call do
        {:when, meta, [{origname, exprmeta, args}, right]} ->
          quote bind_quoted: [
                  expr: Macro.escape(expr, unquote: true),
                  origname: Macro.escape(origname, unquote: true),
                  exprmeta: Macro.escape(exprmeta, unquote: true),
                  args: Macro.escape(args, unquote: true),
                  meta: Macro.escape(meta, unquote: true),
                  right: Macro.escape(right, unquote: true)
                ] do
            require Memoize

            fun = {:when, meta, [{Memoize.__memoname__(origname), exprmeta, args}, right]}
            @memoize_memodefs [{fun, expr} | @memoize_memodefs]
          end

        {origname, exprmeta, args} ->
          quote bind_quoted: [
                  expr: Macro.escape(expr, unquote: true),
                  origname: Macro.escape(origname, unquote: true),
                  exprmeta: Macro.escape(exprmeta, unquote: true),
                  args: Macro.escape(args, unquote: true)
                ] do
            require Memoize

            fun = {Memoize.__memoname__(origname), exprmeta, args}
            @memoize_memodefs [{fun, expr} | @memoize_memodefs]
          end
      end

    fun =
      case call do
        {:when, _, [fun, _]} -> fun
        fun -> fun
      end

    deffun =
      quote bind_quoted: [
              fun: Macro.escape(fun, unquote: true),
              method: Macro.escape(method, unquote: true),
              opts: Macro.escape(opts, unquote: true)
            ] do
        {origname, from, to} = Memoize.__expand_default_args__(fun)
        memoname = Memoize.__memoname__(origname)

        for n <- from..to do
          args = Memoize.__make_args__(n)

          unless Map.has_key?(@memoize_origdefined, {origname, n}) do
            @memoize_origdefined Map.put(@memoize_origdefined, {origname, n}, true)
            case method do
              :def ->
                def unquote(origname)(unquote_splicing(args)) do
                  Memoize.Cache.get_or_run(
                    {__MODULE__, unquote(origname), [unquote_splicing(args)]},
                    fn -> unquote(memoname)(unquote_splicing(args)) end,
                    unquote(opts)
                  )
                end

              :defp ->
                defp unquote(origname)(unquote_splicing(args)) do
                  Memoize.Cache.get_or_run(
                    {__MODULE__, unquote(origname), [unquote_splicing(args)]},
                    fn -> unquote(memoname)(unquote_splicing(args)) end,
                    unquote(opts)
                  )
                end
            end
          end
        end
      end

    [register_memodef, deffun]
  end

  # {:foo, 1, 3} == __expand_default_args__(quote(do: foo(x, y \\ 10, z \\ 20)))
  def __expand_default_args__(fun) do
    {name, args} = Macro.decompose_call(fun)

    is_default_arg = fn
      {:\\, _, _} -> true
      _ -> false
    end

    min_args = Enum.reject(args, is_default_arg)
    {name, length(min_args), length(args)}
  end

  # [] == __make_args__(0)
  # [{:t1, [], Elixir}, {:t2, [], Elixir}] == __make_args__(2)
  def __make_args__(0) do
    []
  end

  def __make_args__(n) do
    for v <- 1..n do
      {:"t#{v}", [], Elixir}
    end
  end

  def __memoname__(origname), do: :"__#{origname}_memoize"

  defmacro __before_compile__(_) do
    quote do
      @memoize_memodefs
      |> Enum.reverse()
      |> Enum.map(fn {memocall, expr} ->
        Code.eval_quoted({:defp, [], [memocall, expr]}, [], __ENV__)
      end)
    end
  end

  def invalidate() do
    Memoize.Cache.invalidate()
  end

  def invalidate(module) do
    Memoize.Cache.invalidate({module, :_, :_})
  end

  def invalidate(module, function) do
    Memoize.Cache.invalidate({module, function, :_})
  end

  def invalidate(module, function, arguments) do
    Memoize.Cache.invalidate({module, function, arguments})
  end

  defdelegate garbage_collect(), to: Memoize.Cache

  def cache_strategy() do
    Memoize.Config.cache_strategy()
  end
end
