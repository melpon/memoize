defmodule Memoize do

  defmacro __using__(_) do
    quote do
      import Memoize, only: [defmemo: 2, defmemop: 2]
      @memodefs []
      @before_compile Memoize
    end
  end

  @doc """
  this code:

      defmemo foo(x, y) when x == 0 do
        y
      end

      defmemo foo(x, y, z \\ 0) when x == 1 do
        y * z
      end

  is converted to:

      def foo(x, y) when x == 0 do
        Memoize.Cache.get_or_run({__MODULE__, :foo, [x, y]}, fn -> __foo_memoize(x, y) end)
      end

      def foo(x, y) when x == 1 do
        Memoize.Cache.get_or_run({__MODULE__, :foo, [x, y]}, fn -> __foo_memoize(x, y) end)
      end

      def foo(x, y, z) when x == 1 do
        Memoize.Cache.get_or_run({__MODULE__, :foo, [x, y, z]}, fn -> __foo_memoize(x, y, z) end)
      end

      def __foo_memoize(x, y) when x == 0 do
        y
      end

      def __foo_memoize(x, y, z \\ 0) when x == 1 do
        y * z
      end
  """
  defmacro defmemo(call, expr \\ nil) do
    define(:def, call, expr)
  end

  defmacro defmemop(call, expr \\ nil) do
    define(:defp, call, expr)
  end

  defp define(method, call, expr) do
    {origname, memocall, origdefs} = init_defmemo(call)
    memoname = memoname(origname)

    register_memodef = quote bind_quoted: [memocall: Macro.escape(memocall), expr: Macro.escape(expr)] do
                         @memodefs [{memocall, expr} | @memodefs]
                       end

    origdefs = for {call, args} <- origdefs do
                 quote do
                   case unquote(method) do
                     :def -> def unquote(call) do
                               Memoize.Cache.get_or_run({__MODULE__, unquote(origname), [unquote_splicing(args)]}, fn -> unquote(memoname)(unquote_splicing(args)) end)
                             end
                     :defp -> defp unquote(call) do
                               Memoize.Cache.get_or_run({__MODULE__, unquote(origname), [unquote_splicing(args)]}, fn -> unquote(memoname)(unquote_splicing(args)) end)
                             end
                   end
                 end
               end

    [register_memodef | origdefs]
  end

  defp memoname(origname), do: :"__#{origname}_memoize"

  defp init_defmemo({:when, meta, [{origname, exprmeta, args} = fun, right | []]}) do
    memocall = {:when, meta, [{memoname(origname), exprmeta, args}, right]}
    origdefs =
      for {name, args, _as, as_args} <- Kernel.Utils.defdelegate(fun, []) do
        call = quote do
                 unquote(name)(unquote_splicing(args)) when unquote(right)
               end

        args = as_args
        {call, args}
      end
    {origname, memocall, origdefs}
  end

  defp init_defmemo({origname, exprmeta, args} = fun) do
    memocall = {memoname(origname), exprmeta, args}
    origdefs =
      for {name, args, _as, as_args} <- Kernel.Utils.defdelegate(fun, []) do
          call = quote do
                   unquote(name)(unquote_splicing(args))
                 end
          args = as_args
          {call, args}
      end
    {origname, memocall, origdefs}
  end

  defmacro __before_compile__(_) do
    quote do
      @memodefs
      |> Enum.reverse()
      |> Enum.map(fn {memocall, expr} ->
                    Code.eval_quoted({:defp, [], [memocall, expr]}, [], __ENV__)
                  end)
    end
  end
end
