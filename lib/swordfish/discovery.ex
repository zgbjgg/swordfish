defmodule Swordfish.Discovery do
  @moduledoc """
  Entry point for discovering application input contracts.
  """

  alias Swordfish.Discovery.AST
  alias Swordfish.Field

  @doc """
  Discovers an application capability contract from a module source file.
  """
  @spec discover_contract(module(), atom()) :: {:ok, Swordfish.Contract.t()} | {:error, term()}
  @spec discover_contract(module(), atom(), keyword()) :: {:ok, Swordfish.Contract.t()} | {:error, term()}
  def discover_contract(module, name, opts \\ [])
      when is_atom(module) and is_atom(name) and is_list(opts) do
    discover(module, opts)
    |> case do
      {:ok, fields} -> {:ok, Swordfish.Contract.new(name, fields)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Discovers public template fields and explicitly requested assign sources.
  """
  @spec discover(module()) :: {:ok, [Field.t()]} | {:error, term()}
  @spec discover(module(), keyword()) :: {:ok, [Field.t()]} | {:error, term()}
  def discover(module, opts \\ []) when is_atom(module) and is_list(opts) do
    explicit_assigns = normalize_explicit_assigns(Keyword.get(opts, :assigns, []))

    module
    |> source_path()
    |> read_source(module, explicit_assigns)
  end

  @doc """
  Discovers fields from an Elixir source string.
  """
  @spec discover_source(binary(), module()) :: {:ok, [Field.t()]} | {:error, term()}
  @spec discover_source(binary(), module(), keyword()) :: {:ok, [Field.t()]} | {:error, term()}
  def discover_source(source, module, explicit_assigns \\ [])
      when is_binary(source) and is_atom(module) and is_list(explicit_assigns) do
    source
    |> Code.string_to_quoted()
    |> parse_source(module, explicit_assigns)
  end

  defp read_source({:ok, path}, module, explicit_assigns) do
    File.read(path)
    |> case do
      {:ok, source} -> discover_source(source, module, explicit_assigns)
      {:error, reason} -> {:error, {:source_read_failed, reason}}
    end
  end

  defp read_source(:error, _module, _explicit_assigns), do: {:error, :source_not_available}

  defp parse_source({:ok, ast}, module, explicit_assigns) do
    find_module_ast(ast, module)
    |> case do
      {:ok, module_ast} -> {:ok, discover_fields(module_ast, module, explicit_assigns)}
      :error -> {:error, :module_not_found}
    end
  end

  defp parse_source({:error, reason}, _module, _explicit_assigns), do: {:error, {:parse_failed, reason}}

  @doc """
  Discovers a field from a field name and its AST expression.
  """
  @spec discover_field(atom(), Macro.t(), module()) :: {:ok, Field.t()} | :dynamic | :error
  def discover_field(name, ast, module) when is_atom(name) and is_atom(module) do
    AST.source(ast, module)
    |> case do
      {:ok, source} ->
        {:ok, build_field(name, source)}
      :dynamic -> :dynamic
      :error -> :error
    end
  end


  defp find_module_ast(ast, module) do
    {_ast, found} =
      Macro.prewalk(ast, nil, &find_module_node(&1, &2, module))

    found || :error
  end

  defp find_module_node(
         {:defmodule, _, [name, _body]} = node,
         nil,
         module
       ) do
    module_name(name)
    |> case do
      ^module -> {node, {:ok, node}}
      _ -> {node, nil}
    end
  end

  defp find_module_node(node, found, _module), do: {node, found}

  defp module_name(name) when is_atom(name), do: name

  defp module_name({:__aliases__, _, parts}) do
    Module.concat(parts)
  end

  defp module_name(_name), do: nil

  defp source_path(module) do
    Code.ensure_loaded(module)
    |> case do
      {:module, ^module} ->
        module
        |> module_source()
        |> normalize_source_path()

      {:error, _reason} ->
        :error
    end
  end

  defp module_source(module) do
    module.__info__(:compile)
    |> Keyword.get(:source)
  end

  defp normalize_source_path(path) when is_binary(path), do: {:ok, path}
  defp normalize_source_path(path) when is_list(path), do: {:ok, List.to_string(path)}
  defp normalize_source_path(_path), do: :error

  defp discover_fields(ast, module, explicit_assigns) do
    {_ast, assigns_fields} = Macro.prewalk(ast, [], &discover_node(&1, &2, module))
    assign_sources = discover_assign_sources(ast, module)
    template_fields = discover_template_fields(module)

    case template_fields do
      {:ok, input_fields} when map_size(input_fields) > 0 ->
        template_discovered =
          assigns_fields
          |> Enum.filter(&Map.has_key?(input_fields, &1.name))
          |> merge_template_fields(input_fields, assigns_fields, assign_sources)

        template_discovered
        |> merge_explicit_assign_fields(assigns_fields, explicit_assigns)
        |> deduplicate_fields()

      _ ->
        assigns_fields
        |> Enum.filter(&(&1.name in explicit_assign_names(explicit_assigns) or explicit_assigns == []))
        |> Enum.map(&apply_explicit_assign_metadata(&1, explicit_assign_spec(explicit_assigns, &1.name)))
        |> deduplicate_fields()
    end
  end

  defp deduplicate_fields(fields) do
    {fields_by_name, names} =
      Enum.reduce(fields, {%{}, []}, &merge_field_by_name/2)

    Enum.map(names, &Map.fetch!(fields_by_name, &1))
  end

  defp merge_field_by_name(field, {fields, names}) do
    Map.get(fields, field.name)
    |> case do
      nil ->
        {Map.put(fields, field.name, field), names ++ [field.name]}

      existing ->
        {Map.put(fields, field.name, merge_duplicate_field(existing, field)), names}
    end
  end

  defp merge_duplicate_field(existing, duplicate) do
    %Field{existing |
      type: duplicate.type,
      multiple?: duplicate.multiple?,
      required?: duplicate.required?,
      description: duplicate.description || existing.description,
      source: preferred_field_source(existing.source, duplicate.source),
      struct: preferred_field_struct(existing.struct, duplicate.struct),
      options: preferred_field_options(existing.options, duplicate.options)
    }
  end

  defp preferred_field_source(source, duplicate) when source in [nil, []], do: duplicate
  defp preferred_field_source(source, _duplicate), do: source

  defp preferred_field_struct(struct, duplicate) when struct in [nil, []], do: duplicate
  defp preferred_field_struct(struct, _duplicate), do: struct

  defp preferred_field_options(options, duplicate) when options in [nil, []], do: duplicate
  defp preferred_field_options(options, _duplicate), do: options

  defp merge_explicit_assign_fields(template_fields, assign_fields, explicit_assigns) do
    explicit_names = explicit_assign_names(explicit_assigns)
    explicit_fields = Enum.filter(assign_fields, &(&1.name in explicit_names))
    template_fields =
      Enum.map(template_fields, fn field ->
        case field.name in explicit_names do
          true -> apply_explicit_assign_metadata(field, explicit_assign_spec(explicit_assigns, field.name))
          false -> field
        end
      end)

    existing_names = MapSet.new(Enum.map(template_fields, & &1.name))

    extra_fields =
      explicit_fields
      |> Enum.reject(&MapSet.member?(existing_names, &1.name))
      |> Enum.map(&apply_explicit_assign_metadata(&1, explicit_assign_spec(explicit_assigns, &1.name)))

    template_fields ++ extra_fields
  end

  defp normalize_explicit_assigns(assigns) when is_list(assigns) do
    Enum.map(assigns, fn
      name when is_atom(name) -> {name, []}
      {name, options} when is_atom(name) and is_list(options) -> {name, options}
    end)
  end

  defp explicit_assign_names(assigns), do: Enum.map(assigns, &elem(&1, 0))

  defp explicit_assign_spec(assigns, name) do
    List.keyfind(assigns, name, 0)
    |> case do
      {^name, options} -> options
      nil -> []
    end
  end

  defp apply_explicit_assign_metadata(field, []) do
    field
  end

  defp apply_explicit_assign_metadata(field, options) do
    field
    |> Map.put(:type, Keyword.get(options, :type, field.type))
    |> Map.put(:value_type, Keyword.get(options, :value_type, field.value_type))
    |> Map.put(:struct, Keyword.get(options, :struct, field.struct))
    |> Map.put(:multiple?, Keyword.get(options, :multiple?, field.multiple?))
    |> Map.put(:required?, Keyword.get(options, :required?, field.required?))
    |> Map.put(:description, Keyword.get(options, :description, field.description))
  end

  defp discover_node(
         {:=, _, [{:assigns, _, _}, value]},
         fields,
         module
       ) do
    {value, extract_fields(value, module) ++ fields}
  end

  defp discover_node(node, fields, _module), do: {node, fields}

  defp extract_fields(value, module) when is_list(value) do
    Enum.flat_map(value, &extract_field(&1, module))
  end

  defp extract_fields(_value, _module), do: []

  defp extract_field({key, value}, module) when is_atom(key) do
    discover_field(key, value, module)
    |> case do
      {:ok, field} -> [field]
      :dynamic -> []
      :error -> []
    end
  end

  defp extract_field(_entry, _module), do: []

  defp merge_template_fields(fields, input_fields, all_assign_fields, assign_sources) do
    discovered_names = MapSet.new(Enum.map(fields, & &1.name))

    fields =
      Enum.map(fields, &merge_discovered_template_field(&1, Map.get(input_fields, &1.name), all_assign_fields, assign_sources))

    input_fields
    |> Map.keys()
    |> Enum.reduce(fields, fn name, acc ->
      case MapSet.member?(discovered_names, name) do
        true -> acc
        false ->
          template_field = Map.fetch!(input_fields, name)
          [enrich_template_field(template_field, assign_sources) | acc]
      end
    end)
  end

  defp merge_discovered_template_field(field, nil, _all_assign_fields, _assign_sources), do: field

  defp merge_discovered_template_field(field, %Field{type: :entity} = template_field, all_assign_fields, assign_sources) do
    %Field{field |
      type: :entity,
      multiple?: true,
      source: preserve_discovered_source(field),
      options: resolve_template_options(template_field.options, all_assign_fields, assign_sources)
    }
  end

  defp merge_discovered_template_field(field, %Field{type: :enum} = template_field, all_assign_fields, assign_sources) do
    %Field{field |
      type: :enum,
      multiple?: template_field.multiple?,
      source: template_field.source,
      options: resolve_template_options(template_field.options, all_assign_fields, assign_sources)
    }
  end

  defp merge_discovered_template_field(field, template_field, _all_assign_fields, _assign_sources) do
    %Field{field |
      type: template_field.type,
      multiple?: template_field.multiple?,
      source: template_field.source,
      options: template_field.options
    }
  end

  defp enrich_template_field(%Field{type: :enum} = field, assign_sources) do
    %Field{field | options: resolve_template_options(field.options, [], assign_sources)}
  end

  defp enrich_template_field(field, _assign_sources), do: field

  defp preserve_discovered_source(%Field{source: nil}), do: nil
  defp preserve_discovered_source(%Field{source: source}), do: source

  defp discover_assign_sources(ast, module) do
    {_ast, sources} =
      Macro.prewalk(ast, %{}, fn
        {:=, _, [{:assigns, _, _}, value]} = node, acc ->
          {node, Map.merge(acc, extract_assign_sources(value, module))}

        node, acc ->
          {node, acc}
      end)

    sources
  end

  defp extract_assign_sources(value, module) when is_list(value) do
    Enum.reduce(value, %{}, fn
      {name, rhs}, acc when is_atom(name) ->
        AST.source(rhs, module)
        |> case do
          {:ok, source} -> Map.put(acc, name, classify_assign_source(source))
          :dynamic -> acc
          :error -> acc
        end

      _entry, acc ->
        acc
    end)
  end

  defp extract_assign_sources(_value, _module), do: %{}

  defp classify_assign_source({:function, resolver}) when is_function(resolver, 0),
    do: {:resolver, {:function, resolver}}

  defp classify_assign_source(source) when is_list(source) do
    case function_source?(source) do
      true -> {:resolver, source}
      false -> {:literal, source}
    end
  end

  defp classify_assign_source(source), do: {:literal, source}

  defp function_source?([module, function, arguments])
       when is_atom(module) and is_atom(function) and is_list(arguments),
       do: true

  defp function_source?(_source), do: false

  defp resolve_template_options({:assign, name}, fields, assign_sources) do
    Map.get(assign_sources, name)
    |> case do
      {:literal, value} -> normalize_select_values(value)
      {:resolver, source} -> {:resolver, source}
      nil -> resolve_template_options_from_fields(name, fields)
    end
  end

  defp resolve_template_options(options, _fields, _assign_sources), do: options

  defp resolve_template_options_from_fields(name, fields) do
    Enum.find(fields, &(&1.name == name))
    |> case do
      %Field{type: :enum, source: source} when is_list(source) -> normalize_select_values(source)
      %Field{source: source} -> resolve_enum_source(source, name)
      _ -> {:assign, name}
    end
  end

  defp resolve_enum_source(source, name) do
    case safe_option_source?(source, name) do
      true -> {:resolver, source}
      false -> {:assign, name}
    end
  end

  defp safe_option_source?(source, name) when source in [nil, {:template, name}], do: false
  defp safe_option_source?({:function, resolver}, _name) when is_function(resolver, 0), do: true

  defp safe_option_source?([module, function, arguments], _name)
       when is_atom(module) and is_atom(function) and is_list(arguments),
       do: function != :|>

  defp safe_option_source?({:case, _selector, branches}, _name) when is_list(branches) do
    Enum.all?(branches, &safe_option_branch?/1)
  end

  defp safe_option_source?(source, _name) when is_list(source), do: true
  defp safe_option_source?(_source, _name), do: false

  defp safe_option_branch?({_expected, source}), do: safe_option_source?(source, nil)
  defp safe_option_branch?(_branch), do: false

  defp discover_template_fields(module) do
    module
    |> template_path()
    |> read_template()
  end

  defp read_template({:ok, path}) do
    File.read(path)
    |> case do
      {:ok, source} -> {:ok, template_input_names(source)}
      {:error, _reason} -> :error
    end
  end

  defp read_template(:error), do: :error

  defp template_path(module) do
    source_path(module)
    |> case do
      {:ok, path} ->
        path
        |> Path.rootname()
        |> template_candidates()
        |> find_existing_template()

      :error ->
        :error
    end
  end

  defp template_candidates(root) do
    [
      root <> ".html.heex",
      root <> ".html.eex",
      root <> ".html.leex"
    ]
  end

  defp find_existing_template([path | paths]) do
    case File.exists?(path) do
      true -> {:ok, path}
      false -> find_existing_template(paths)
    end
  end

  defp find_existing_template([]), do: :error

  defp template_input_names(source) do
    source
    |> template_fields()
    |> Enum.reduce(%{}, &put_template_field/2)
  end

  defp template_fields(source) do
    phoenix_form_helper_fields(source) ++ heex_input_fields(source)
  end

  defp heex_input_fields(source) do
    html_fields = Regex.scan(
      ~r/<(input|select|textarea)\b([^>]*)>/is,
      source,
      capture: :all_but_first
    )
    |> Enum.map(&heex_html_field/1)
    |> Enum.reject(&is_nil/1)

    component_fields =
      Regex.scan(
        ~r/<\.input\b[^>]*\bfield=\{@[^}]*\[:([a-zA-Z0-9_?]+)\][^}]*\}/is,
        source,
        capture: :all_but_first
      )
      |> Enum.map(&heex_component_field/1)

    html_fields ++ component_fields
  end

  defp heex_html_field([tag, attributes]) do
    Regex.run(~r/\bname=[\"](?:[^\"]*\[)?([a-zA-Z0-9_?]+)\]?[^\"]*[\"]/i, attributes)
    |> case do
      [_, name] ->
        field_name = String.to_atom(name)
        multiple? = heex_multiple?(tag, attributes)
        type = heex_input_type(tag, attributes, multiple?)

        %Field{
          name: field_name,
          type: type,
          multiple?: multiple?,
          source: {:template, field_name}
        }

      _ ->
        nil
    end
  end

  defp heex_component_field([name]) do
    field_name = String.to_atom(name)

    %Field{
      name: field_name,
      type: :string,
      multiple?: false,
      source: {:template, field_name}
    }
  end

  defp heex_input_type("input", attributes, _multiple?) do
    Regex.run(~r/\btype=[\"]([^\"]+)[\"]/i, attributes)
    |> case do
      [_, "checkbox"] -> :boolean
      [_, "number"] -> :integer
      [_, "date"] -> :date
      [_, "datetime-local"] -> :datetime
      _ -> :string
    end
  end

  defp heex_input_type("select", _attributes, _multiple?), do: :enum
  defp heex_input_type("textarea", _attributes, _multiple?), do: :string
  defp heex_input_type(_tag, _attributes, _multiple?), do: :string

  defp heex_multiple?("select", attributes), do: Regex.match?(~r/\bmultiple\b(?:\s*=)?/i, attributes)
  defp heex_multiple?(_tag, _attributes), do: false

  defp put_template_field(%Field{type: :enum, options: options} = field, fields)
       when is_list(options) do
    Map.get(fields, field.name)
    |> case do
      %Field{type: :enum, options: existing_options} = existing when is_list(existing_options) ->
        Map.put(fields, field.name, %Field{existing | options: Enum.uniq(existing_options ++ options)})

      _ ->
        Map.put_new(fields, field.name, field)
    end
  end

  defp put_template_field(field, fields) do
    Map.put_new(fields, field.name, field)
  end

  defp phoenix_form_helper_fields(source) do
    form_fields =
      source
      |> phoenix_form_helpers()
      |> Enum.map(&phoenix_form_field/1)
      |> Enum.reject(&is_nil/1)

    form_fields
  end

  defp phoenix_form_helpers(source) do
    Regex.scan(
      ~r/\b(select|checkbox|radio_button|text_input|number_input|date_select|datetime_select|date_input|datetime_input)\s+f\s*,\s*:?[a-zA-Z0-9_?]+(?:\s*,[^\n]*)?/,
      source
    )
    |> Enum.map(&List.first/1)
  end

  defp phoenix_form_field(expression) do
    Regex.run(~r/\b(select|checkbox|radio_button|text_input|number_input|date_select|datetime_select|date_input|datetime_input)\s+f\s*,\s*:([a-zA-Z0-9_?]+)/, expression)
    |> case do
      [_, helper, name] ->
        field_name = String.to_atom(name)
        multiple? = phoenix_helper_multiple?(helper, expression)
        options = phoenix_helper_options(helper, expression)

        %Field{
          name: field_name,
          type: phoenix_helper_type(helper, options),
          multiple?: multiple?,
          source: {:template, field_name},
          options: options
        }

      _ ->
        nil
    end
  end

  defp phoenix_helper_type("checkbox", _options), do: :boolean
  defp phoenix_helper_type("number_input", _options), do: :integer
  defp phoenix_helper_type("date_select", _options), do: :date
  defp phoenix_helper_type("date_input", _options), do: :date
  defp phoenix_helper_type("datetime_select", _options), do: :datetime
  defp phoenix_helper_type("datetime_input", _options), do: :datetime
  defp phoenix_helper_type("select", _options), do: :enum
  defp phoenix_helper_type("radio_button", _options), do: :enum
  defp phoenix_helper_type(_helper, _options), do: :string


  defp phoenix_helper_options("select", expression), do: phoenix_options(expression)
  defp phoenix_helper_options("radio_button", expression), do: phoenix_radio_options(expression)
  defp phoenix_helper_options(_helper, _expression), do: nil

  defp phoenix_options(expression) do
    Regex.run(~r/\bselect\s+f\s*,\s*:[a-zA-Z0-9_?]+\s*,\s*(.*?)(?=,\s*(?:value|class|prompt|phx_|id)\s*:|\s*(?:%>)?\s*\z)/, expression)
    |> case do
      [_, value] -> normalize_template_options(value)
      _ -> nil
    end
  end

  defp phoenix_radio_options(expression) do
    Regex.run(~r/\bradio_button\s+f\s*,\s*:[a-zA-Z0-9_?]+\s*,\s*([^,\s]+)/, expression)
    |> case do
      [_, value] -> [normalize_option_value(value)]
      _ -> nil
    end
  end

  defp normalize_template_options(value) do
    value = String.trim(value)

    value
    |> normalize_assign_or_source()
  end

  defp normalize_assign_or_source(value) do
    case String.starts_with?(value, "@") do
      true -> {:assign, String.trim_leading(value, "@") |> String.to_atom()}
      false -> parse_select_source(value)
    end
  end

  defp parse_select_source(value) do
    value
    |> Code.string_to_quoted()
    |> normalize_select_source_result()
  end

  defp normalize_select_source_result({:ok, ast}), do: normalize_select_source(ast)
  defp normalize_select_source_result({:error, _reason}), do: nil

  defp normalize_select_source(ast) do
    Swordfish.Discovery.AST.source(ast, __MODULE__)
    |> case do
      {:ok, values} when is_list(values) -> normalize_select_values(values)
      _ -> nil
    end
  end

  defp normalize_select_values(values) do
    Enum.map(values, &normalize_select_value/1)
  end

  defp normalize_select_value({label, value}) when is_binary(label), do: value
  defp normalize_select_value(value), do: value

  defp normalize_option_value(value) do
    value
    |> String.trim()
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
    |> String.trim_leading("\'")
    |> String.trim_trailing("\'")
    |> normalize_option_atom()
  end

  defp normalize_option_atom(<<":", rest::binary>>), do: String.to_atom(rest)
  defp normalize_option_atom(value), do: value

  defp phoenix_helper_multiple?("select", expression) do
    Regex.match?(~r/\bmultiple\s*:/, expression)
  end

  defp phoenix_helper_multiple?("checkbox", _expression), do: false
  defp phoenix_helper_multiple?(_helper, _expression), do: false

  defp build_field(name, source) do
    %Field{
      name: name,
      type: field_type(source),
      multiple?: multiple?(source),
      source: source
    }
  end

  defp field_type({:case, _selector, branches}) when is_list(branches) do
    case entity_case?(branches) do
      true -> :entity
      false -> :fn
    end
  end

  defp field_type([module, function, arguments])
       when is_atom(module) and is_atom(function) and is_list(arguments),
       do: function_type(function)

  defp field_type(value) when is_boolean(value), do: :boolean
  defp field_type(value) when is_binary(value), do: :string
  defp field_type(value) when is_integer(value), do: :integer
  defp field_type(value) when is_list(value), do: :enum
  defp field_type(_source), do: :unknown

  defp function_type(function) when function in [:simple_list, :simple_list_for_agents], do: :entity
  defp function_type(_function), do: :fn

  defp multiple?({:case, _selector, branches}) when is_list(branches), do: entity_case?(branches)

  defp multiple?([module, function, arguments])
       when is_atom(module) and is_atom(function) and is_list(arguments),
       do: function in [:simple_list, :simple_list_for_agents]

  defp multiple?(values) when is_list(values), do: true
  defp multiple?(_value), do: false

  defp entity_case?(branches) do
    branches != [] and
      Enum.all?(branches, &entity_branch?/1)
  end

  defp entity_branch?({_expected, [module, function, arguments]})
       when is_atom(module) and is_atom(function) and is_list(arguments),
       do: function in [:simple_list, :simple_list_for_agents]

  defp entity_branch?(_branch), do: false
end
