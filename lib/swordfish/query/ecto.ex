defmodule Swordfish.Query.Ecto do
  @moduledoc """
  Compiles an `Swordfish.Query` into an `Ecto.Query`.

  The compiler assumes the query has already passed through
  `Swordfish.Query.Validator`.
  """

  import Ecto.Query

  alias Swordfish.Query
  alias Swordfish.Query.{And, Or, Not, Condition, Order}
  alias Swordfish.Query.Ecto.{Builder, JoinPlanner}
  alias Swordfish.Resource

  @doc """
  Compiles an Swordfish.Query against an Swordfish.Resource.

  Returns an Ecto query or an error.
  """
  @spec compile(Query.t(), Resource.t()) :: {:ok, Ecto.Query.t()} | {:error, term()}
  def compile(%Query{} = query, %Resource{} = resource) do
    Swordfish.Query.Validator.validate(query, resource)
    |> case do
      {:ok, validated_query} -> compile_plan(validated_query, resource)
      {:error, reason} -> {:error, reason}
    end
  end

  defp compile_plan(query, resource) do
    JoinPlanner.plan(query, resource)
    |> case do
      {:ok, plan} -> {:ok, build_query(query, plan)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_query(%Query{resource: schema} = query, plan) do
    base = from(record in schema)

    base
    |> apply_joins(plan)
    |> apply_where(query.where, plan)
    |> apply_order_by(query.order_by, plan)
    |> apply_group_by(query.group_by, plan)
    |> apply_limit(query.limit)
    |> apply_offset(query.offset)
  end

  defp apply_joins(query, %{joins: joins}) do
    Enum.reduce(joins, query, &apply_join/2)
  end

  defp apply_join(%{association: association, binding: binding, parent_binding: parent_binding}, query) do
    parent_index = Map.get(query.aliases, parent_binding, 0)
    Builder.apply_association_join(query, association, binding, parent_index)
  end

  defp apply_where(query, nil, _plan), do: query

  defp apply_where(query, expression, plan) do
    dynamic = compile_expression(expression, plan)
    where(query, ^dynamic)
  end

  defp apply_order_by(query, orders, plan) do
    Enum.reduce(orders, query, &apply_order(&1, &2, plan))
  end

  defp apply_order(%Order{path: path, direction: direction}, query, plan) do
    binding = JoinPlanner.binding_for_path(plan, path)
    field_name = List.last(path)
    field_expr = dynamic_field(binding, field_name)
    order = [{direction, field_expr}]

    order_by(query, ^order)
  end

  defp apply_group_by(query, [], _plan), do: query

  defp apply_group_by(query, paths, plan) do
    Enum.reduce(paths, query, &apply_group(&1, &2, plan))
  end

  defp apply_group(path, query, plan) do
    binding = JoinPlanner.binding_for_path(plan, path)
    field_name = List.last(path)
    group = [dynamic_field(binding, field_name)]

    group_by(query, ^group)
  end

  defp apply_limit(query, nil), do: query
  defp apply_limit(query, limit), do: limit(query, ^limit)

  defp apply_offset(query, nil), do: query
  defp apply_offset(query, offset), do: offset(query, ^offset)

  defp compile_expression(%Condition{path: path, operator: operator, value: value}, plan) do
    binding = JoinPlanner.binding_for_path(plan, path)
    field_name = List.last(path)
    field_expr = dynamic_field(binding, field_name)

    compile_condition(operator, field_expr, value)
  end

  defp compile_expression(%And{conditions: conditions}, plan) do
    Enum.reduce(conditions, true, &compile_and(&1, &2, plan))
  end

  defp compile_expression(%Or{conditions: conditions}, plan) do
    case conditions do
      [] ->
        false

      [first | rest] ->
        Enum.reduce(rest, compile_expression(first, plan), &compile_or(&1, &2, plan))
    end
  end

  defp compile_expression(%Not{expression: expression}, plan) do
    dynamic(not (^compile_expression(expression, plan)))
  end

  defp dynamic_field(:root, field_name) do
    dynamic([root], field(root, ^field_name))
  end

  defp dynamic_field(binding, field_name) do
    dynamic([{^binding, root}], field(root, ^field_name))
  end

  defp compile_and(expression, acc, plan) do
    dynamic(^acc and ^compile_expression(expression, plan))
  end

  defp compile_or(expression, acc, plan) do
    dynamic(^acc or ^compile_expression(expression, plan))
  end

  defp compile_condition(:eq, field_expr, value), do: dynamic(^field_expr == ^value)
  defp compile_condition(:neq, field_expr, value), do: dynamic(^field_expr != ^value)
  defp compile_condition(:gt, field_expr, value), do: dynamic(^field_expr > ^value)
  defp compile_condition(:gte, field_expr, value), do: dynamic(^field_expr >= ^value)
  defp compile_condition(:lt, field_expr, value), do: dynamic(^field_expr < ^value)
  defp compile_condition(:lte, field_expr, value), do: dynamic(^field_expr <= ^value)
  defp compile_condition(:in, field_expr, value), do: dynamic(^field_expr in ^value)
  defp compile_condition(:not_in, field_expr, value), do: dynamic(^field_expr not in ^value)
  defp compile_condition(:contains, field_expr, value), do: dynamic(like(^field_expr, ^"%#{value}%"))
  defp compile_condition(:starts_with, field_expr, value), do: dynamic(like(^field_expr, ^"#{value}%"))
  defp compile_condition(:ends_with, field_expr, value), do: dynamic(like(^field_expr, ^"%#{value}"))
  defp compile_condition(:is_nil, field_expr, _value), do: dynamic(is_nil(^field_expr))
  defp compile_condition(:is_not_nil, field_expr, _value), do: dynamic(not is_nil(^field_expr))
end
