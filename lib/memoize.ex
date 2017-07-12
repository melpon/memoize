defmodule Memoize do

  defmacro __using__(_) do
    quote do
      import Memoize, only: [defmemo: 1,
                             defmemo: 2,
                             defmemo: 3,
                             defmemop: 1,
                             defmemop: 2,
                             defmemop: 3]
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

      defmemo __foo_memoize(0, y) do
        y
      end

      defmemo __foo_memoize(x, y) when x == 1 do
        y * z
      end

      defmemo __foo_memoize(x, y, z \\ 0) when x == 2 do
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
      expr_or_opts == nil -> {[], nil}
      # expr_or_opts is expr
      Keyword.has_key?(expr_or_opts, :do) -> {[], expr_or_opts}
      # expr_or_opts is opts
      true -> {expr_or_opts, nil}
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
    {memocall, fun} = init_defmemo(call)

    register_memodef = quote bind_quoted: [memocall: Macro.escape(memocall), expr: Macro.escape(expr)] do
                         @memoize_memodefs [{memocall, expr} | @memoize_memodefs]
                       end

    {origname, from, to} = expand_default_args(fun)
    memoname = memoname(origname)

    origdefs =
      for n <- from..to do
        args = make_args(n)
        quote do
          unless Map.has_key?(@memoize_origdefined, {unquote(origname), unquote(n)}) do
            @memoize_origdefined Map.put(@memoize_origdefined, {unquote(origname), unquote(n)}, true)
            case unquote(method) do
              :def ->
                def unquote(origname)(unquote_splicing(args)) do
                  Memoize.Cache.get_or_run({__MODULE__, unquote(origname), [unquote_splicing(args)]}, fn -> unquote(memoname)(unquote_splicing(args)) end, unquote(opts))
                end
              :defp ->
                defp unquote(origname)(unquote_splicing(args)) do
                  Memoize.Cache.get_or_run({__MODULE__, unquote(origname), [unquote_splicing(args)]}, fn -> unquote(memoname)(unquote_splicing(args)) end, unquote(opts))
                end
            end
          end
        end
      end

    [register_memodef | origdefs]
  end

  # {:foo, 1, 3} == expand_default_args(quote(do: foo(x, y \\ 10, z \\ 20)))
  defp expand_default_args(fun) do
    {name, args} = Macro.decompose_call(fun)
    is_default_arg = fn {:\\, _, _} -> true
                        _ -> false end
    min_args = Enum.reject(args, is_default_arg)
    {name, length(min_args), length(args)}
  end

  # [] == make_args(0)
  # [{:t1, [], Elixir}, {:t2, [], Elixir}] == make_args(2)
  defp make_args(0) do
    []
  end
  defp make_args(n) do
    for v <- 1..n do
      {:"t#{v}", [], Elixir}
    end
  end

  defp memoname(origname), do: :"__#{origname}_memoize"

  defp init_defmemo({:when, meta, [{origname, exprmeta, args} = fun, right | []]}) do
    memocall = {:when, meta, [{memoname(origname), exprmeta, args}, right]}
    {memocall, fun}
  end

  defp init_defmemo({origname, exprmeta, args} = fun) do
    memocall = {memoname(origname), exprmeta, args}
    {memocall, fun}
  end

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

  def memory_strategy() do
    Memoize.Application.memory_strategy()
  end
end
