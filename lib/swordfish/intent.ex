defmodule Swordfish.Intent do
  @moduledoc """
  Provider-neutral representation of a validated LLM tool call.
  """

  @schema_keys [
    {"type", :type},
    {"required", :required},
    {"additionalProperties", :additional_properties},
    {"items", :items},
    {"enum", :enum},
    {"format", :format}
  ]

  @schema_types %{
    "object" => :object,
    "array" => :array,
    "string" => :string,
    "integer" => :integer,
    "boolean" => :boolean,
    "number" => :number
  }
  @schema_formats %{"date" => :date, "date-time" => :date_time}
  alias Swordfish.Tool

  @type t :: %__MODULE__{
          id: binary() | nil,
          name: binary(),
          arguments: map()
        }

  defstruct [:id, :name, arguments: %{}]

  @doc """
  Builds an intent from a provider-neutral tool call.
  """
  @spec new(binary() | nil, binary(), map()) :: t()
  def new(id, name, arguments) when is_binary(name) and is_map(arguments) do
    %__MODULE__{id: id, name: name, arguments: arguments}
  end

  @doc """
  Builds an intent from a normalized provider tool call.
  """
  @spec from_tool_call(map()) :: {:ok, t()} | {:error, term()}
  def from_tool_call(%{id: id, name: name, arguments: arguments})
      when (is_binary(id) or is_nil(id)) and is_binary(name) and is_map(arguments) do
    {:ok, new(id, name, arguments)}
  end

  def from_tool_call(_tool_call), do: {:error, :invalid_tool_call}

  @doc """
  Validates an intent against an allowed list of provider-neutral tools.
  """
  @spec validate(t(), [Tool.t()]) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = intent, tools) when is_list(tools) do
    find_tool(tools, intent.name)
    |> case do
      {:ok, tool} -> validate_arguments(intent, tool.input_schema)
      :error -> {:error, {:unknown_tool, intent.name}}
    end
  end

  defp find_tool([], _name), do: :error

  defp find_tool([%Tool{name: name} = tool | _rest], name), do: {:ok, tool}
  defp find_tool([_tool | rest], name), do: find_tool(rest, name)

  defp validate_arguments(intent, schema) do
    schema = normalize_schema(schema)
    arguments = normalize_arguments(intent.arguments, schema)
    normalized_intent = %{intent | arguments: arguments}

    validate_value(arguments, schema, [:arguments])
    |> case do
      :ok -> {:ok, normalized_intent}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_arguments(arguments, %{type: :object, properties: properties})
       when is_map(arguments) do
    Map.new(arguments, &normalize_argument(&1, properties))
  end

  defp normalize_arguments(value, _schema), do: value

  defp normalize_argument({name, value}, properties) do
    property_schema(properties, name)
    |> case do
      {:ok, _property_name, schema} ->
        {name, normalize_argument_value(value, normalize_schema(schema))}

      :error ->
        {name, value}
    end
  end

  defp normalize_argument_value(nil, %{type: :array, entities: entities}) when is_list(entities),
    do: []

  defp normalize_argument_value(nil, %{type: :array, items: %{enum: values}})
       when is_list(values),
       do: []

  defp normalize_argument_value(value, %{type: :array, items: schema}) when is_list(value) do
    Enum.map(value, &normalize_argument_value(&1, schema))
  end

  defp normalize_argument_value(value, %{enum: values}) when is_list(values) do
    normalize_enum_argument(value, values)
  end

  defp normalize_argument_value(value, _schema), do: value

  defp normalize_enum_argument(value, values) do
    Enum.find(values, &(enum_wire_value(&1) == value))
    |> case do
      {_label, enum_value} -> enum_value
      nil -> value
      enum_value -> enum_value
    end
  end

  defp enum_wire_value({label, _value}), do: label
  defp enum_wire_value(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_wire_value(value), do: value

  defp normalize_schema(schema) when is_map(schema) do
    schema
    |> normalize_schema_keys()
    |> normalize_schema_properties()
    |> normalize_schema_items()
  end

  defp normalize_schema(schema), do: schema

  defp normalize_schema_keys(schema) do
    Enum.reduce(@schema_keys, schema, &normalize_schema_key/2)
  end

  defp normalize_schema_key({string_key, atom_key}, schema) do
    Map.pop(schema, string_key)
    |> case do
      {nil, schema} -> schema
      {value, schema} -> Map.put_new(schema, atom_key, normalize_schema_value(atom_key, value))
    end
  end

  defp normalize_schema_value(:type, value), do: Map.get(@schema_types, value, value)
  defp normalize_schema_value(:format, value), do: Map.get(@schema_formats, value, value)
  defp normalize_schema_value(_key, value), do: value

  defp normalize_schema_properties(%{properties: properties} = schema) when is_map(properties) do
    %{schema | properties: normalize_property_schemas(properties)}
  end

  defp normalize_schema_properties(schema), do: schema

  defp normalize_property_schemas(properties) do
    Map.new(properties, &normalize_property_schema/1)
  end

  defp normalize_property_schema({name, property_schema}) do
    {name, normalize_schema(property_schema)}
  end

  defp normalize_schema_items(%{items: items} = schema) do
    %{schema | items: normalize_schema(items)}
  end

  defp normalize_schema_items(schema), do: schema

  defp validate_value(value, %{type: :object} = schema, path) when is_map(value) do
    validate_required(value, Map.get(schema, :required, []), path)
    |> case do
      :ok -> validate_properties(value, schema, path)
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_value(value, %{type: :object}, path),
    do: {:error, {:invalid_type, path, :object, value}}

  defp validate_value(value, %{type: :array, items: item_schema}, path) when is_list(value) do
    validate_array_items(value, item_schema, path, 0)
  end

  defp validate_value(value, %{type: :array}, path),
    do: {:error, {:invalid_type, path, :array, value}}

  defp validate_value(value, %{type: :string, format: :date} = schema, path) do
    validate_scalar(value, schema, :string, path)
  end

  defp validate_value(value, %{type: :string, format: :date_time} = schema, path) do
    validate_scalar(value, schema, :string, path)
  end

  defp validate_value(value, %{type: :string} = schema, path) do
    validate_scalar(value, schema, :string, path)
  end

  defp validate_value(value, %{type: :integer} = schema, path) do
    validate_scalar(value, schema, :integer, path)
  end

  defp validate_value(value, %{type: :boolean} = schema, path) do
    validate_scalar(value, schema, :boolean, path)
  end

  defp validate_value(value, %{type: :number} = schema, path) do
    validate_scalar(value, schema, :number, path)
  end

  defp validate_value(value, %{type: type}, path),
    do: {:error, {:invalid_type, path, type, value}}

  defp validate_required(_value, [], _path), do: :ok

  defp validate_required(value, [name | rest], path) do
    fetch_argument(value, name)
    |> case do
      {:ok, _value} -> validate_required(value, rest, path)
      :error -> {:error, {:missing_required, path ++ [name]}}
    end
  end

  defp validate_properties(value, schema, path) do
    properties = Map.get(schema, :properties, %{})
    validate_known_properties(value, Map.keys(value), properties, schema, path)
  end

  defp validate_known_properties(_value, [], _properties, _schema, _path), do: :ok

  defp validate_known_properties(value, [name | rest], properties, schema, path) do
    properties
    |> property_schema(name)
    |> validate_known_property(name, value, rest, properties, schema, path)
  end

  defp validate_known_property(
         {:ok, property_name, property_schema},
         _name,
         value,
         rest,
         properties,
         schema,
         path
       ) do
    value
    |> fetch_argument(property_name)
    |> validate_known_argument(
      property_schema,
      property_name,
      value,
      rest,
      properties,
      schema,
      path
    )
  end

  defp validate_known_property(:error, name, _value, _rest, _properties, _schema, path),
    do: {:error, {:unknown_argument, path ++ [name]}}

  defp validate_known_argument(
         {:ok, argument},
         property_schema,
         property_name,
         value,
         rest,
         properties,
         schema,
         path
       ) do
    argument
    |> validate_property_argument(property_schema, property_name, schema, path)
    |> continue_known_property(value, rest, properties, schema, path)
  end

  defp validate_known_argument(
         :error,
         _property_schema,
         _property_name,
         value,
         rest,
         properties,
         schema,
         path
       ),
       do: validate_known_properties(value, rest, properties, schema, path)

  defp continue_known_property(:ok, value, rest, properties, schema, path),
    do: validate_known_properties(value, rest, properties, schema, path)

  defp continue_known_property({:error, reason}, _value, _rest, _properties, _schema, _path),
    do: {:error, reason}

  defp validate_property_argument(nil, _property_schema, property_name, schema, path) do
    case property_required?(schema, property_name) do
      true -> {:error, {:invalid_type, path ++ [property_name], :non_nil, nil}}
      false -> :ok
    end
  end

  defp validate_property_argument(argument, property_schema, property_name, _schema, path) do
    validate_value(argument, property_schema, path ++ [property_name])
  end

  defp property_required?(schema, property_name) do
    Enum.any?(Map.get(schema, :required, []), &same_property_name?(&1, property_name))
  end

  defp same_property_name?(left, right) when is_atom(left) and is_binary(right),
    do: Atom.to_string(left) == right

  defp same_property_name?(left, right) when is_binary(left) and is_atom(right),
    do: left == Atom.to_string(right)

  defp same_property_name?(left, right), do: left == right

  defp property_schema(properties, name) do
    Map.fetch(properties, name)
    |> case do
      {:ok, schema} -> {:ok, name, schema}
      :error -> property_schema_by_string_key(properties, name)
    end
  end

  defp property_schema_by_string_key(properties, name) when is_atom(name) do
    string_name = Atom.to_string(name)

    Map.fetch(properties, string_name)
    |> case do
      {:ok, schema} -> {:ok, string_name, schema}
      :error -> :error
    end
  end

  defp property_schema_by_string_key(properties, name) when is_binary(name) do
    find_atom_property(properties, name)
    |> case do
      {:ok, property_name, schema} -> {:ok, property_name, schema}
      :error -> :error
    end
  end

  defp property_schema_by_string_key(_properties, _name), do: :error

  defp find_atom_property(properties, name) do
    Enum.find_value(properties, :error, &match_property_name(&1, name))
  end

  defp match_property_name({property_name, schema}, name) when is_atom(property_name) do
    case Atom.to_string(property_name) == name do
      true -> {:ok, property_name, schema}
      false -> nil
    end
  end

  defp match_property_name(_property, _name), do: nil

  defp fetch_argument(value, name) when is_atom(name) do
    Map.fetch(value, name)
    |> case do
      {:ok, argument} -> {:ok, argument}
      :error -> Map.fetch(value, Atom.to_string(name))
    end
  end

  defp fetch_argument(value, name), do: Map.fetch(value, name)

  defp validate_array_items([], _schema, _path, _index), do: :ok

  defp validate_array_items([value | rest], schema, path, index) do
    validate_value(value, schema, path ++ [index])
    |> case do
      :ok -> validate_array_items(rest, schema, path, index + 1)
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_scalar(value, schema, type, path) do
    Map.get(schema, :enum)
    |> case do
      values when is_list(values) -> validate_enum(value, values, path)
      _ -> validate_type(value, type, path)
    end
  end

  defp validate_type(value, :string, _path) when is_binary(value), do: :ok
  defp validate_type(value, :integer, _path) when is_integer(value), do: :ok
  defp validate_type(value, :boolean, _path) when is_boolean(value), do: :ok
  defp validate_type(value, :number, _path) when is_number(value), do: :ok

  defp validate_type(value, type, path), do: {:error, {:invalid_type, path, type, value}}

  defp validate_enum(value, values, path) do
    application_values = Enum.map(values, &enum_application_value/1)

    case value in application_values do
      true -> :ok
      false -> {:error, {:invalid_enum_value, path, value}}
    end
  end

  defp enum_application_value({_label, value}), do: value
  defp enum_application_value(value), do: value
end
