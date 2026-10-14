defmodule Swordfish.Query.Decoder do
  @moduledoc "Decodes structured tool arguments into Swordfish.Query."

  alias Swordfish.Query.Builder, as: Q
  alias Swordfish.Query.Operator
  alias Swordfish.Query.Path
  alias Swordfish.Resource

  @doc "Converts decoded tool-call arguments into a Swordfish query."
  @spec from_map(Resource.t(), map()) :: {:ok, Swordfish.Query.t()} | {:error, term()}
  def from_map(%Resource{} = resource, params) when is_map(params) do
    decode_filters(Map.get(params, "filters", []), resource)
    |> case do
      {:ok, where} -> build_query(where, resource, params)
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_filters(filters, resource) when is_list(filters) do
    filters
    |> Enum.map(&decode_condition(&1, resource))
    |> collect_conditions()
  end

  defp decode_filters(_filters, _resource), do: {:error, :invalid_filters}

  defp decode_condition(%{"path" => path, "operator" => operator} = params, resource)
       when is_list(path) and is_binary(operator) do
    {decode_path(path, resource), decode_operator(operator)}
    |> build_condition(params)
  end

  defp decode_condition(_condition, _resource), do: {:error, :invalid_filter}

  defp build_condition({{:ok, decoded_path}, {:ok, decoded_operator}}, params) do
    {:ok, Q.condition(decoded_path, decoded_operator, Map.get(params, "value"))}
  end

  defp build_condition({{:error, reason}, _}, _params), do: {:error, reason}
  defp build_condition({_, {:error, reason}}, _params), do: {:error, reason}

  defp decode_path(path, resource) do
    resource
    |> resolve_allowed_path(path, [])
    |> validate_resolved_path(resource)
  end

  defp validate_resolved_path({:ok, atoms}, resource) do
    Path.resolve(resource, atoms)
    |> case do
      {:ok, _} -> {:ok, atoms}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_resolved_path({:error, reason}, _resource), do: {:error, reason}

  defp resolve_allowed_path(_resource, [], _acc), do: {:error, :empty_path}

  defp resolve_allowed_path(resource, [part], acc) when is_binary(part) do
    allowed_field(resource, part)
    |> case do
      {:ok, field} -> {:ok, Enum.reverse([field | acc])}
      :error -> {:error, {:field_not_allowed, resource.name, part}}
    end
  end

  defp resolve_allowed_path(resource, [part | rest], acc) when is_binary(part) do
    allowed_association(resource, part)
    |> case do
      {:ok, association} ->
        next = Resource.new(
          association.name,
          association.module,
          fields: association.fields,
          associations: association.associations,
          max_depth: resource.max_depth
        )

        resolve_allowed_path(next, rest, [association.name | acc])

      :error -> {:error, {:association_not_allowed, resource.name, part}}
    end
  end

  defp resolve_allowed_path(_resource, _path, _acc), do: {:error, :invalid_path}

  defp allowed_field(%Resource{fields: fields}, name) do
    Enum.find(fields, &(Atom.to_string(&1) == name))
    |> case do
      nil -> :error
      field -> {:ok, field}
    end
  end

  defp allowed_association(%Resource{associations: associations}, name) do
    Enum.find(associations, &(Atom.to_string(elem(&1, 0)) == name))
    |> case do
      nil -> :error
      {_key, association} -> {:ok, association}
    end
  end

  defp decode_operator(operator) do
    Enum.find(Operator.all(), &(Atom.to_string(&1) == operator))
    |> case do
      nil -> {:error, {:invalid_operator, operator}}
      value -> {:ok, value}
    end
  end

  defp collect_conditions(results) do
    Enum.find(results, &match?({:error, _}, &1))
    |> case do
      {:error, reason} -> {:error, reason}
      nil ->
        conditions = Enum.map(results, &elem(&1, 1))
        {:ok, wrap_conditions(conditions)}
    end
  end

  defp wrap_conditions([]), do: nil
  defp wrap_conditions([condition]), do: condition
  defp wrap_conditions(conditions), do: Q.and_(conditions)

  defp build_query(where, resource, params) do
    query = Q.query(resource.schema, where: where, limit: Map.get(params, "limit"))
    {:ok, query}
  end
end
