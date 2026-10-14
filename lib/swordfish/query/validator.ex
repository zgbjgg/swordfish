defmodule Swordfish.Query.Validator do
  @moduledoc "Validation boundary between untrusted AI output and Ecto."

  alias Swordfish.Query
  alias Swordfish.Query.{And, Or, Not, Condition, Order}
  alias Swordfish.Query.Operator
  alias Swordfish.Query.Path
  alias Swordfish.Query.Value
  alias Swordfish.Resource

  @doc """
  Validates a query against a Swordfish resource.
  """
  @spec validate(Query.t(), Resource.t()) :: {:ok, Query.t()} | {:error, term()}
  def validate(%Query{} = query, %Resource{} = resource) do
    query
    |> validate_resource(resource)
    |> continue_validation(query, resource)
  end

  defp continue_validation(:ok, query, resource) do
    validate_query_parts(query, resource)
    |> case do
      :ok -> {:ok, query}
      {:error, reason} -> {:error, reason}
    end
  end

  defp continue_validation({:error, reason}, _query, _resource), do: {:error, reason}

  defp validate_resource(%Query{resource: schema}, %Resource{schema: schema}), do: :ok
  defp validate_resource(_, _), do: {:error, :resource_mismatch}

  defp validate_query_parts(query, resource) do
    [
      validate_expression(query.where, resource),
      validate_expression(query.having, resource),
      validate_order_by(query.order_by, resource),
      validate_group_by(query.group_by, resource),
      validate_limit(query.limit),
      validate_offset(query.offset)
    ]
    |> run_results()
  end

  defp validate_expression(nil, _resource), do: :ok

  defp validate_expression(%Condition{} = condition, resource) do
    condition
    |> validate_operator()
    |> continue_condition_validation(condition, resource)
  end

  defp validate_expression(%And{conditions: conditions}, resource),
    do: validate_all(conditions, resource)

  defp validate_expression(%Or{conditions: conditions}, resource),
    do: validate_all(conditions, resource)

  defp validate_expression(%Not{expression: expression}, resource),
    do: validate_expression(expression, resource)

  defp validate_expression(_, _), do: {:error, :invalid_expression}

  defp validate_operator(%Condition{operator: operator}) do
    case Operator.valid?(operator) do
      true -> :ok
      false -> {:error, {:invalid_operator, operator}}
    end
  end

  defp continue_condition_validation(:ok, condition, resource) do
    Path.resolve(resource, condition.path)
    |> case do
      {:ok, resolved} -> validate_condition_value(condition, resolved.type)
      {:error, reason} -> {:error, reason}
    end
  end

  defp continue_condition_validation({:error, reason}, _condition, _resource),
    do: {:error, reason}

  defp validate_condition_value(condition, type) do
    validate_value(condition.operator, condition.value, type)
  end

  defp validate_all(expressions, resource) do
    expressions
    |> Enum.map(&validate_expression(&1, resource))
    |> run_results()
  end

  defp run_results(results) do
    Enum.reduce_while(results, :ok, &continue_result/2)
  end

  defp continue_result(:ok, :ok), do: {:cont, :ok}
  defp continue_result({:error, reason}, :ok), do: {:halt, {:error, reason}}

  defp validate_order_by(orders, resource) do
    orders
    |> Enum.map(&validate_order(&1, resource))
    |> run_results()
  end

  defp validate_order(%Order{path: path, direction: direction}, resource)
       when direction in [:asc, :desc] do
    Path.resolve(resource, path)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_order(_, _), do: {:error, :invalid_order}

  defp validate_group_by(paths, resource) do
    paths
    |> Enum.map(&Path.resolve(resource, &1))
    |> Enum.map(&normalize_path_result/1)
    |> run_results()
  end

  defp normalize_path_result({:ok, _}), do: :ok
  defp normalize_path_result({:error, reason}), do: {:error, reason}

  defp validate_limit(nil), do: :ok
  defp validate_limit(limit) when is_integer(limit) and limit > 0 and limit <= 1000, do: :ok
  defp validate_limit(_), do: {:error, :invalid_limit}

  defp validate_offset(nil), do: :ok
  defp validate_offset(offset) when is_integer(offset) and offset >= 0, do: :ok
  defp validate_offset(_), do: {:error, :invalid_offset}

  defp validate_value(operator, _value, _type)
       when operator in [:is_nil, :is_not_nil],
       do: :ok

  defp validate_value(operator, value, _type)
       when operator in [:in, :not_in] do
    is_list(value)
    |> case do
      true -> :ok
      false -> {:error, {:invalid_value, operator}}
    end
  end

  defp validate_value(_operator, value, type) do
    case Value.valid_for_type?(value, type) do
      true -> :ok
      false -> {:error, {:invalid_value_for_type, value, type}}
    end
  end
end
