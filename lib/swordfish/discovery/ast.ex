defmodule Swordfish.Discovery.AST do
  @moduledoc """
  AST helpers used by Swordfish application discovery.
  """

  @doc """
  Discovers a callable source from an Elixir expression.

  Remote calls are represented as `[module, function, arguments]`.
  Complex expressions are represented as function resolvers.
  Static lists are returned as their evaluated value when they contain only
  compile-time literals.
  """
  @spec source(Macro.t(), module()) :: {:ok, term()} | :dynamic | :error
  def source(ast, module) when is_atom(module) do
    source_with_aliases(ast, module, module_aliases(module))
  end

  defp source_with_aliases({{:., _, [module_ast, function]}, _, arguments}, _module, aliases)
       when is_atom(function) and is_list(arguments) do
    module_name(module_ast, aliases)
    |> case do
      {:ok, module} -> {:ok, [module, function, normalize_arguments(arguments)]}
      :error -> :error
    end
  end

  defp source_with_aliases({:|>, _, _} = ast, module, aliases) do
    expression = normalize_expression(ast, module, aliases)
    {:ok, {:function, fn -> expression end}}
  end

  defp source_with_aliases({function, _, arguments}, module, _aliases)
       when is_atom(function) and is_list(arguments) do
    {:ok, [module, function, normalize_arguments(arguments)]}
  end

  defp source_with_aliases({name, _metadata, context}, _module, _aliases)
       when is_atom(name) and (is_atom(context) or is_nil(context)) do
    {:ok, {:context, [name]}}
  end

  defp source_with_aliases(ast, _module, _aliases) when is_list(ast) do
    static_value(ast)
    |> case do
      {:ok, value} -> {:ok, value}
      :dynamic -> :dynamic
    end
  end

  defp source_with_aliases(ast, _module, _aliases) do
    static_value(ast)
    |> case do
      {:ok, value} -> {:ok, value}
      :dynamic -> :dynamic
    end
  end

  defp normalize_expression(ast, module, aliases) do
    Macro.prewalk(ast, &normalize_expression_node(&1, module, aliases))
  end

  defp normalize_expression_node({name, _metadata, context}, _module, _aliases)
       when is_atom(name) and is_atom(context) do
    {:context, [name]}
  end

  defp normalize_expression_node({:__aliases__, _metadata, parts}, _module, aliases)
       when is_list(parts) do
    resolve_alias(parts, aliases)
  end

  defp normalize_expression_node(
         {:|>, metadata, [left, {function, call_metadata, arguments}]},
         module,
         aliases
       )
       when is_atom(function) and is_list(arguments) do
    arity = length(arguments) + 1

    case function_exported?(module, function, arity) do
      true ->
        normalized_arguments =
          [left | arguments]
          |> Enum.map(&normalize_expression(&1, module, aliases))

        {{:., metadata, [module, function]}, call_metadata, normalized_arguments}

      false ->
        {:|>, metadata,
         [normalize_expression(left, module, aliases), {function, call_metadata, arguments}]}
    end
  end

  defp normalize_expression_node(
         {{:., _metadata, [receiver, field]}, _call_metadata, []} = node,
         _module,
         _aliases
       ) do
    context_path(receiver, field)
    |> case do
      {:ok, path} -> {:context, path}
      :error -> node
    end
  end

  defp normalize_expression_node({:., _metadata, [receiver, field]} = node, _module, _aliases)
       when is_atom(field) do
    context_path(receiver, field)
    |> case do
      {:ok, path} -> {:context, path}
      :error -> node
    end
  end

  defp normalize_expression_node({function, metadata, arguments}, module, _aliases)
       when is_atom(function) and is_list(arguments) do
    case function_exported?(module, function, length(arguments)) do
      true ->
        {{:., metadata, [module, function]}, [], Enum.map(arguments, &normalize_ast/1)}

      false ->
        {function, metadata, arguments}
    end
  end

  defp normalize_expression_node(node, _module, _aliases), do: node

  defp normalize_arguments(arguments) do
    Enum.map(arguments, &normalize_ast/1)
  end

  defp normalize_ast({{:., _metadata, [receiver, field]}, _call_metadata, []}) do
    normalize_field_access(receiver, field)
  end

  defp normalize_ast({:., _metadata, [receiver, field]}) when is_atom(field) do
    normalize_field_access(receiver, field)
  end

  defp normalize_ast({{:., _metadata, [{name, _name_metadata, nil}, field]}, _call_metadata, []})
       when is_atom(name) and is_atom(field) do
    {:context, [name, field]}
  end

  defp normalize_ast({name, _metadata, context})
       when is_atom(name) and (is_atom(context) or is_nil(context)) do
    {:context, [name]}
  end

  defp normalize_ast({left, metadata, right}) when is_list(metadata) do
    {normalize_ast(left), [], normalize_ast_value(right)}
  end

  defp normalize_ast(value), do: value

  defp normalize_ast_value(value) when is_list(value), do: Enum.map(value, &normalize_ast/1)
  defp normalize_ast_value(value), do: normalize_ast(value)

  defp context_path({name, _metadata, context}, field)
       when is_atom(name) and (is_atom(context) or is_nil(context)) and is_atom(field) do
    {:ok, [name, field]}
  end

  defp context_path({{:., _metadata, [receiver, parent_field]}, _call_metadata, []}, field)
       when is_atom(parent_field) and is_atom(field) do
    append_context_path(receiver, parent_field, field)
  end

  defp context_path({:., _metadata, [receiver, parent_field]}, field)
       when is_atom(parent_field) and is_atom(field) do
    append_context_path(receiver, parent_field, field)
  end

  defp context_path(_receiver, _field), do: :error

  defp append_context_path(receiver, parent_field, field) do
    context_path(receiver, parent_field)
    |> case do
      {:ok, path} -> {:ok, path ++ [field]}
      :error -> :error
    end
  end

  defp normalize_field_access(receiver, field) do
    context_path(receiver, field)
    |> case do
      {:ok, path} -> {:context, path}
      :error -> {:., [], [normalize_ast(receiver), field]}
    end
  end

  defp module_aliases(module) do
    module_source(module)
    |> case do
      {:ok, source} -> extract_aliases(source)
      :error -> %{}
    end
  end

  defp module_source(module) do
    Code.ensure_loaded(module)
    |> case do
      {:module, ^module} ->
        module.__info__(:compile)
        |> Keyword.get(:source)
        |> normalize_source_path()

      {:error, _reason} ->
        :error
    end
  end

  defp normalize_source_path(path) when is_binary(path) do
    File.read(path)
  end

  defp normalize_source_path(path) when is_list(path) do
    path
    |> List.to_string()
    |> File.read()
  end

  defp normalize_source_path(_path), do: :error

  defp extract_aliases(source) do
    Code.string_to_quoted(source)
    |> case do
      {:ok, ast} ->
        {_ast, aliases} = Macro.prewalk(ast, %{}, &collect_alias/2)
        aliases

      {:error, _reason} ->
        %{}
    end
  end

  defp collect_alias({:alias, _metadata, [multi_alias_ast]}, aliases) do
    {multi_alias_ast, put_multi_aliases(multi_alias_ast, aliases)}
  end

  defp collect_alias({:alias, _metadata, [module_ast, options]}, aliases)
       when is_list(options) do
    alias_ast = Keyword.get(options, :as)
    {module_ast, put_alias(module_ast, alias_ast, aliases)}
  end

  defp collect_alias(node, aliases), do: {node, aliases}

  defp put_alias({:__aliases__, _metadata, parts}, nil, aliases) when is_list(parts) do
    module = Module.concat(parts)
    alias_name = List.last(parts)
    Map.put(aliases, alias_name, module)
  end

  defp put_alias(
         {:__aliases__, _metadata, parts},
         {:__aliases__, _alias_metadata, alias_parts},
         aliases
       )
       when is_list(parts) and is_list(alias_parts) do
    module = Module.concat(parts)
    alias_name = List.last(alias_parts)
    Map.put(aliases, alias_name, module)
  end

  defp put_alias(_module_ast, _alias_ast, aliases), do: aliases

  defp put_multi_aliases(
         {{:., _metadata, [{:__aliases__, _base_metadata, base_parts}, :{}]}, _call_metadata,
          alias_asts},
         aliases
       )
       when is_list(base_parts) and is_list(alias_asts) do
    Enum.reduce(alias_asts, aliases, &put_multi_alias(&1, base_parts, &2))
  end

  defp put_multi_aliases(_ast, aliases), do: aliases

  defp put_multi_alias({:__aliases__, _metadata, parts}, base_parts, aliases)
       when is_list(parts) do
    module = Module.concat(base_parts ++ parts)
    alias_name = List.last(parts)
    Map.put(aliases, alias_name, module)
  end

  defp put_multi_alias(_ast, _base_parts, aliases), do: aliases

  defp resolve_alias([first | rest], aliases) when is_atom(first) do
    Map.get(aliases, first)
    |> case do
      nil -> Module.concat([first | rest])
      module -> Module.concat([module | rest])
    end
  end

  defp resolve_alias(parts, _aliases), do: Module.concat(parts)

  defp module_name({:__aliases__, _, parts}, aliases) when is_list(parts) do
    {:ok, resolve_alias(parts, aliases)}
  end

  defp module_name(module, _aliases) when is_atom(module), do: {:ok, module}
  defp module_name(_, _aliases), do: :error

  defp static_value(value) when is_atom(value), do: {:ok, value}
  defp static_value(value) when is_binary(value), do: {:ok, value}
  defp static_value(value) when is_integer(value), do: {:ok, value}
  defp static_value(value) when is_float(value), do: {:ok, value}
  defp static_value(value) when is_boolean(value), do: {:ok, value}
  defp static_value(nil), do: {:ok, nil}

  defp static_value({:__aliases__, _, parts}) do
    {:ok, Module.concat(parts)}
  end

  defp static_value({left, right}) do
    case {static_value(left), static_value(right)} do
      {{:ok, left_value}, {:ok, right_value}} -> {:ok, {left_value, right_value}}
      _ -> :dynamic
    end
  end

  defp static_value({:%{}, _, entries}) do
    entries
    |> Enum.reduce_while({:ok, %{}}, &static_map_entry/2)
  end

  defp static_value(list) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, &static_list_entry/2)
    |> reverse_static_list()
  end

  defp static_value(_), do: :dynamic

  defp static_map_entry({key, value}, {:ok, acc}) do
    case {static_value(key), static_value(value)} do
      {{:ok, key_value}, {:ok, value_value}} ->
        {:cont, {:ok, Map.put(acc, key_value, value_value)}}

      _ ->
        {:halt, :dynamic}
    end
  end

  defp static_map_entry(_, _acc), do: {:halt, :dynamic}

  defp static_list_entry(value, {:ok, acc}) do
    static_value(value)
    |> case do
      {:ok, value} -> {:cont, {:ok, [value | acc]}}
      :dynamic -> {:halt, :dynamic}
    end
  end

  defp static_list_entry(_value, _acc), do: {:halt, :dynamic}

  defp reverse_static_list({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_static_list(:dynamic), do: :dynamic
end
