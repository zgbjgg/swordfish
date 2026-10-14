defmodule Swordfish.Provider.Schema do
  @moduledoc "Converts provider-neutral Swordfish schemas into JSON-compatible tool schemas."

  @doc """
  Converts a Swordfish schema into a JSON-compatible provider schema.
  """
  @spec to_json(map()) :: map()
  def to_json(schema) when is_map(schema) do
    schema
    |> prepare_entity_metadata()
    |> encode_schema_entries()
    |> normalize_object_schema()
  end

  defp prepare_entity_metadata(schema) when is_map(schema) do
    schema
    |> maybe_add_entity_metadata()
    |> Map.new(&prepare_schema_entry/1)
  end

  defp prepare_entity_metadata(value), do: value

  defp prepare_schema_entry({key, value}) when is_map(value) do
    {key, prepare_entity_metadata(value)}
  end

  defp prepare_schema_entry({key, value}) when is_list(value) do
    {key, Enum.map(value, &prepare_entity_metadata/1)}
  end

  defp prepare_schema_entry(entry), do: entry

  defp maybe_add_entity_metadata(%{entities: entities} = schema) when is_list(entities) do
    entity_provider_metadata(entities, Map.get(schema, :entity_struct, [:id, :name]))
    |> case do
      nil -> schema
      metadata -> put_entity_provider_metadata(schema, metadata)
    end
  end

  defp maybe_add_entity_metadata(schema), do: schema

  defp entity_provider_metadata([], _struct), do: nil

  defp entity_provider_metadata(entities, struct) do
    ids = Enum.map(entities, &Map.get(&1, :id))
    labels = Enum.map(entities, &entity_label(&1, struct))

    case Enum.all?(ids, &is_integer/1) do
      true ->
        description = entity_options_description(ids, labels)
        %{ids: ids, description: description}

      false ->
        nil
    end
  end

  defp entity_label(entity, struct) do
    label_fields = Enum.reject(struct, &(&1 == :id))

    Enum.find_value(label_fields, &entity_label_value(entity, &1))
    |> case do
      nil -> nil
      label -> label
    end
  end

  defp entity_label_value(entity, field) do
    Map.get(entity, field)
    |> case do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp entity_options_description(ids, labels) do
    options =
      ids
      |> Enum.zip(labels)
      |> Enum.map(&format_entity_option/1)
      |> Enum.join(", ")

    "Available values: #{options}"
  end

  defp format_entity_option({id, nil}), do: "#{id}"
  defp format_entity_option({id, label}), do: "#{id} = #{label}"

  defp put_entity_provider_metadata(%{type: :array, items: items} = schema, %{
         ids: ids,
         description: description
       })
       when is_map(items) do
    %{schema | items: Map.merge(items, %{enum: ids, description: description})}
  end

  defp put_entity_provider_metadata(schema, %{ids: ids, description: description}) do
    schema
    |> Map.put(:enum, ids)
    |> Map.put(:description, description)
  end

  defp encode_schema_entries(schema) do
    schema
    |> Enum.reject(&internal_schema_entry?/1)
    |> Enum.reject(&empty_enum_entry?/1)
    |> Map.new(&encode_schema_entry/1)
  end

  defp internal_schema_entry?({key, nil}) when key in [:description, "description"], do: true
  defp internal_schema_entry?({key, _value}) when key in [:name, "name"], do: true
  defp internal_schema_entry?({key, _value}) when key in [:entities, "entities"], do: true

  defp internal_schema_entry?({key, _value}) when key in [:entity_struct, "entity_struct"],
    do: true

  defp internal_schema_entry?({key, _value}) when key in [:entity_source, "entity_source"],
    do: true

  defp internal_schema_entry?({key, _value}) when key in [:enum_source, "enum_source"], do: true
  defp internal_schema_entry?(_entry), do: false

  defp empty_enum_entry?({key, values}) when key in [:enum, "enum"] and values == [], do: true

  defp empty_enum_entry?({_key, value}) when is_map(value) do
    Map.get(value, :enum) == [] or Map.get(value, "enum") == []
  end

  defp empty_enum_entry?(_entry), do: false

  defp encode_schema_entry({key, value}) do
    {encode_key(key), encode_schema_value(key, value)}
  end

  defp encode_key(key) when is_atom(key), do: Atom.to_string(key)
  defp encode_key(key), do: key

  defp encode_schema_value(key, :date_time) when key in [:format, "format"], do: "date-time"

  defp encode_schema_value(key, value)
       when key in [:type, "type", :format, "format"] and is_atom(value) do
    Atom.to_string(value)
  end

  defp encode_schema_value(key, values) when key in [:required, "required"] and is_list(values) do
    Enum.map(values, &encode_key/1)
  end

  defp encode_schema_value(key, values) when key in [:enum, "enum"] and is_list(values) do
    Enum.map(values, &encode_enum_value/1)
  end

  defp encode_schema_value(_key, value) when is_map(value) do
    to_json(value)
  end

  defp encode_schema_value(_key, value) when is_list(value) do
    Enum.map(value, &encode_schema_value(nil, &1))
  end

  defp encode_schema_value(_key, value) when is_atom(value) do
    Atom.to_string(value)
  end

  defp encode_schema_value(_key, value), do: value

  defp normalize_object_schema(%{"type" => "object", "properties" => properties} = schema)
       when is_map(properties) do
    required = Map.get(schema, "required", [])
    property_names = Map.keys(properties)

    schema
    |> Map.put("properties", normalize_properties(properties, required))
    |> Map.put("required", property_names)
    |> Map.put("additionalProperties", false)
  end

  defp normalize_object_schema(schema), do: schema

  defp normalize_properties(properties, required) do
    Map.new(properties, &normalize_property(&1, required))
  end

  defp normalize_property({name, property}, required) do
    {name, normalize_optional_property(property, name in required)}
  end

  defp normalize_optional_property(%{"type" => "boolean"} = property, _required?), do: property

  defp normalize_optional_property(property, true), do: property

  defp normalize_optional_property(%{"type" => type} = property, false) do
    property
    |> Map.put("type", [type, "null"])
    |> normalize_nullable_enum()
  end

  defp normalize_optional_property(property, false), do: property

  defp normalize_nullable_enum(%{"enum" => values} = property) when is_list(values) do
    Map.put(property, "enum", values ++ [nil])
  end

  defp normalize_nullable_enum(property), do: property

  defp encode_enum_value({label, _value}) when is_binary(label), do: label
  defp encode_enum_value(value) when is_atom(value), do: Atom.to_string(value)
  defp encode_enum_value(value), do: value
end
