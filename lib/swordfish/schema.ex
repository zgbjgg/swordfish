defmodule Swordfish.Schema do
  @moduledoc """
  Builds provider-independent schemas from Swordfish contracts.
  """

  alias Swordfish.Contract
  alias Swordfish.Field

  @doc """
  Builds a provider-independent object schema from a contract.
  """
  @spec from_contract(Contract.t()) :: {:ok, map()} | {:error, term()}
  def from_contract(%Contract{} = contract) do
    fields_schema(contract.fields, %{}, [])
    |> case do
      {:ok, properties, required} ->
        {:ok,
         %{
           type: :object,
           name: contract.name,
           description: contract.description,
           properties: properties,
           required: Enum.reverse(required)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Builds a provider-independent schema for a field.
  """
  @spec field(Field.t()) :: {:ok, map()} | {:error, term()}
  def field(%Field{} = field) do
    field_schema(field)
    |> case do
      {:ok, schema} ->
        {:ok, Map.put(schema, :description, field.description)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fields_schema([], properties, required), do: {:ok, properties, required}

  defp fields_schema([field | rest], properties, required) do
    field(field)
    |> case do
      {:ok, schema} ->
        next_required = add_required(field, required)
        fields_schema(rest, Map.put(properties, field.name, schema), next_required)

      {:error, reason} ->
        {:error, {:invalid_field, field.name, reason}}
    end
  end

  defp add_required(%Field{required?: true, name: name}, required), do: [name | required]
  defp add_required(_field, required), do: required

  defp field_schema(%Field{type: :string, multiple?: false}), do: {:ok, %{type: :string}}
  defp field_schema(%Field{type: :integer, multiple?: false}), do: {:ok, %{type: :integer}}
  defp field_schema(%Field{type: :boolean, multiple?: false}), do: {:ok, %{type: :boolean}}

  defp field_schema(%Field{type: :date, multiple?: false}),
    do: {:ok, %{type: :string, format: :date}}

  defp field_schema(%Field{type: :datetime, multiple?: false}),
    do: {:ok, %{type: :string, format: :date_time}}

  defp field_schema(%Field{type: :string, multiple?: true}), do: array_schema(:string)
  defp field_schema(%Field{type: :integer, multiple?: true}), do: array_schema(:integer)
  defp field_schema(%Field{type: :boolean, multiple?: true}), do: array_schema(:boolean)

  defp field_schema(%Field{type: :date, multiple?: true}),
    do: array_schema(%{type: :string, format: :date})

  defp field_schema(%Field{type: :datetime, multiple?: true}),
    do: array_schema(%{type: :string, format: :date_time})

  defp field_schema(%Field{type: :enum, options: values, multiple?: multiple?})
       when is_list(values) do
    enum_schema(values, multiple?)
  end

  defp field_schema(%Field{type: :enum, source: values, multiple?: multiple?})
       when is_list(values) do
    enum_schema(values, multiple?)
  end

  defp field_schema(%Field{type: :enum, options: {:resolver, source}, multiple?: multiple?}) do
    dynamic_enum_schema(source, multiple?)
  end

  defp field_schema(%Field{type: :enum, options: {:assign, _assign}}) do
    {:error, :dynamic_enum_options}
  end

  defp field_schema(%Field{type: :entity, value_type: nil}) do
    {:error, :entity_schema_requires_value_type}
  end

  defp field_schema(%Field{
         type: :entity,
         value_type: value_type,
         source: source,
         struct: struct,
         multiple?: false
       }) do
    {:ok, entity_schema(schema_type(value_type), source, entity_struct(struct), false)}
  end

  defp field_schema(%Field{
         type: :entity,
         value_type: value_type,
         source: source,
         struct: struct,
         multiple?: true
       }) do
    {:ok, entity_schema(schema_type(value_type), source, entity_struct(struct), true)}
  end

  defp field_schema(%Field{type: :fn}) do
    {:error, :function_source_requires_field_type}
  end

  defp field_schema(%Field{type: type}) do
    {:error, {:unsupported_field_type, type}}
  end

  defp schema_type(:string), do: :string
  defp schema_type(:integer), do: :integer
  defp schema_type(:boolean), do: :boolean
  defp schema_type(:number), do: :number
  defp schema_type(:float), do: :number
  defp schema_type(:id), do: :integer
  defp schema_type(type), do: type

  defp array_schema(item_type), do: {:ok, %{type: :array, items: item_schema(item_type)}}

  defp entity_struct(nil), do: [:id, :name]
  defp entity_struct(struct), do: struct

  defp entity_schema(value_type, nil, struct, false),
    do: %{type: value_type, entity_struct: struct}

  defp entity_schema(value_type, nil, struct, true),
    do: %{type: :array, items: %{type: value_type}, entity_struct: struct, default: []}

  defp entity_schema(value_type, source, struct, false),
    do: %{type: value_type, entity_source: source, entity_struct: struct}

  defp entity_schema(value_type, source, struct, true) do
    %{
      type: :array,
      items: %{type: value_type},
      entity_source: source,
      entity_struct: struct,
      default: []
    }
  end

  defp item_schema(type) when is_atom(type), do: %{type: type}
  defp item_schema(schema), do: schema

  defp dynamic_enum_schema(source, false), do: {:ok, %{type: :string, enum_source: source}}

  defp dynamic_enum_schema(source, true),
    do: {:ok, %{type: :array, items: %{type: :string, enum_source: source}, default: []}}

  defp enum_schema(values, false), do: {:ok, %{type: :string, enum: values}}

  defp enum_schema(values, true),
    do: {:ok, %{type: :array, items: %{type: :string, enum: values}, default: []}}
end
