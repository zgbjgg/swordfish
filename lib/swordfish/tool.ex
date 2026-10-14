defmodule Swordfish.Tool do
  @moduledoc "Provider-neutral representation of an LLM tool."

  alias Swordfish.Contract
  alias Swordfish.Context
  alias Swordfish.Resolver
  alias Swordfish.Schema

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          input_schema: map(),
          handler: function() | nil
        }

  defstruct [:name, :description, :input_schema, :handler]

  @doc "Builds a provider-neutral tool from a contract."
  @spec from_contract(Contract.t()) :: {:ok, t()} | {:error, term()}
  def from_contract(%Contract{} = contract) do
    Schema.from_contract(contract)
    |> case do
      {:ok, input_schema} ->
        {:ok,
         new(
           Atom.to_string(contract.name),
           contract.description || "",
           input_schema
         )}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Resolves dynamic enum sources using approved runtime context."
  @spec resolve(t(), Context.t()) :: {:ok, t()} | {:error, term()}
  @spec resolve(t()) :: {:ok, t()} | {:error, term()}
  def resolve(%__MODULE__{} = tool, context \\ Context.new()) do
    resolve_schema(tool.input_schema, context)
    |> case do
      {:ok, input_schema} -> {:ok, %{tool | input_schema: input_schema}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Creates a provider-neutral Swordfish tool."
  @spec new(String.t(), String.t(), map(), function() | nil) :: t()
  def new(name, description, input_schema, handler \\ nil) do
    %__MODULE__{
      name: name,
      description: description,
      input_schema: input_schema,
      handler: handler
    }
  end
  defp resolve_schema(%{properties: properties} = schema, context) when is_map(properties) do
    resolve_properties(properties, context, %{})
    |> case do
      {:ok, resolved_properties} -> {:ok, %{schema | properties: resolved_properties}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_schema(schema, _context), do: {:ok, schema}

  defp resolve_properties(properties, _context, resolved) when map_size(properties) == 0,
    do: {:ok, resolved}

  defp resolve_properties(properties, context, resolved) do
    [entry | rest] = Map.to_list(properties)
    resolve_property(entry, rest, context, resolved)
  end

  defp resolve_property({name, schema}, remaining, context, resolved) do
    resolve_field_schema(schema, context)
    |> case do
      {:ok, resolved_schema} ->
        resolve_properties(Map.new(remaining), context, Map.put(resolved, name, resolved_schema))
      {:error, reason} ->
        {:error, {:invalid_property, name, reason}}
    end
  end

  defp resolve_field_schema(%{entity_source: source} = schema, context) do
    struct = Map.get(schema, :entity_struct, [:id, :name])

    source
    |> Resolver.resolve(context)
    |> resolve_entity_source_result(schema, struct)
  end

  defp resolve_field_schema(%{enum_source: source} = schema, context) do
    Resolver.resolve(source, context)
    |> case do
      {:ok, values} when is_list(values) ->
        {:ok, Map.delete(Map.put(schema, :enum, values), :enum_source)}
      {:ok, value} ->
        {:error, {:invalid_enum_source_result, value}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_field_schema(%{items: items} = schema, context) when is_map(items) do
    resolve_field_schema(items, context)
    |> case do
      {:ok, resolved_items} -> {:ok, %{schema | items: resolved_items}}
      {:error, reason} -> {:error, reason}
    end
  end
  defp resolve_field_schema(schema, _context), do: {:ok, schema}

  defp resolve_entities(entities, struct) do
    Enum.reduce_while(entities, {:ok, []}, &resolve_entity(&1, &2, struct))
    |> case do
      {:ok, resolved_entities} -> {:ok, Enum.reverse(resolved_entities)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_entity(entity, {:ok, resolved}, struct) when is_map(entity) do
    entity
    |> validate_entity_id()
    |> continue_entity_resolution(entity, resolved, struct)
  end

  defp resolve_entity(entity, _acc, _struct), do: {:halt, {:error, {:invalid_entity, entity}}}

  defp resolve_entity_source_result({:ok, entities}, schema, struct) when is_list(entities) do
    resolve_entities(entities, struct)
    |> case do
      {:ok, resolved_entities} ->
        {:ok, schema |> Map.put(:entities, resolved_entities) |> Map.delete(:entity_source)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_entity_source_result({:ok, value}, _schema, _struct), do: {:error, {:invalid_entity_source_result, value}}
  defp resolve_entity_source_result({:error, reason}, _schema, _struct), do: {:error, reason}

  defp validate_entity_id(entity) do
    if Map.has_key?(entity, :id), do: :ok, else: {:error, {:invalid_entity, entity}}
  end

  defp continue_entity_resolution(:ok, entity, resolved, struct) do
    missing_entity_fields(entity, struct)
    |> case do
      [] -> {:cont, {:ok, [Map.take(entity, struct) | resolved]}}
      missing -> {:halt, {:error, {:missing_entity_fields, missing, entity}}}
    end
  end

  defp continue_entity_resolution({:error, reason}, _entity, _resolved, _struct), do: {:halt, {:error, reason}}

  defp missing_entity_fields(entity, struct) do
    Enum.reject(struct, &Map.has_key?(entity, &1))
  end
end
