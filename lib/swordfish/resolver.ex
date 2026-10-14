defmodule Swordfish.Resolver do
  @moduledoc """
  Executes resolver sources discovered by Swordfish.
  """

  alias Swordfish.Context

  @doc "Resolves a discovered source using approved runtime context."
  @spec resolve(term()) :: {:ok, term()} | {:error, term()}
  @spec resolve(term(), Context.t()) :: {:ok, term()} | {:error, term()}
  def resolve(source, context \\ Context.new())

  def resolve({:function, resolver}, %Context{} = context) when is_function(resolver, 0) do
    expression = resolver.()

    resolve_expression(expression, context)
    |> case do
      {:ok, resolved_expression} -> execute_expression(resolved_expression)
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, {:resolver_failed, error}}
  end

  def resolve({:case, selector, branches}, %Context{} = context) when is_list(branches) do
    selector
    |> resolve_argument(context)
    |> resolve_case_branch(branches, context)
  end

  def resolve([module, function, arguments], %Context{} = context)
      when is_atom(module) and is_atom(function) and is_list(arguments) do
    resolve_arguments(arguments, context, [])
    |> case do
      {:ok, resolved_arguments} -> execute(module, function, resolved_arguments)
      {:error, reason} -> {:error, reason}
    end
  end

  def resolve(_source, _context), do: {:error, :invalid_resolver_source}

  defp resolve_case_branch({:ok, value}, branches, context) do
    branches
    |> find_branch(value)
    |> resolve_branch(value, context)
  end

  defp resolve_case_branch({:error, reason}, _branches, _context), do: {:error, reason}

  defp resolve_branch({:ok, source}, _value, context), do: resolve(source, context)
  defp resolve_branch(:error, value, _context), do: {:error, {:no_resolver_branch, value}}

  defp resolve_arguments([], _context, resolved), do: {:ok, Enum.reverse(resolved)}

  defp resolve_arguments([argument | rest], context, resolved) do
    resolve_argument(argument, context)
    |> case do
      {:ok, value} -> resolve_arguments(rest, context, [value | resolved])
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_argument({:context, path}, context) when is_list(path) do
    Context.get_path(context, path)
    |> case do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_context, path}}
    end
  end

  defp resolve_argument(value, _context), do: {:ok, value}

  defp resolve_expression(expression, context) do
    {_expression, result} =
      Macro.prewalk(expression, {:ok, context}, fn
        {:context, path}, {:ok, current_context} ->
          Context.get_path(current_context, path)
          |> case do
            {:ok, value} -> {value, {:ok, current_context}}
            :error -> {{:context, path}, {:error, {:missing_context, path}}}
          end

        node, acc ->
          {node, acc}
      end)

    result
    |> case do
      {:ok, _context} -> {:ok, replace_context_values(expression, context)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp replace_context_values(expression, context) do
    Macro.prewalk(expression, fn
      {:context, path} ->
        Context.get_path(context, path)
        |> case do
          {:ok, value} -> Macro.escape(value)
          :error -> {:context, path}
        end

      node -> node
    end)
  end

  defp find_branch([{expected, source} | _rest], value) when expected == value, do: {:ok, source}
  defp find_branch([_branch | rest], value), do: find_branch(rest, value)
  defp find_branch([], _value), do: :error

  defp execute_expression(expression) do
    Code.eval_quoted(expression, [], __ENV__)
    |> case do
      {value, _bindings} -> {:ok, value}
    end
  rescue
    error -> {:error, {:resolver_failed, error}}
  end

  defp execute(module, function, arguments) do
    {:ok, :erlang.apply(module, function, arguments)}
  rescue
    error -> {:error, {:resolver_failed, error}}
  end
end
