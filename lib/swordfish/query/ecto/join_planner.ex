defmodule Swordfish.Query.Ecto.JoinPlanner do
  @moduledoc """
  Builds the association join plan required by an Swordfish.Query.

  The planner converts semantic paths such as:

      [:customer, :account_manager, :name]

  into a stable set of Ecto association joins.
  """

  alias Swordfish.Query
  alias Swordfish.Query.{Condition, And, Or, Not, Order}
  alias Swordfish.Resource

  @type join :: %{
          path: [atom()],
          association: atom(),
          binding: atom(),
          parent_binding: atom()
        }

  @type t :: %{
          joins: [join()],
          bindings: %{optional([atom()]) => atom()}
        }

  @doc """
  Builds an association join plan for a validated query.
  """
  @spec plan(Query.t(), Resource.t()) :: {:ok, t()} | {:error, term()}
  def plan(%Query{} = query, %Resource{} = resource) do
    paths =
      []
      |> collect_expression_paths(query.where)
      |> collect_expression_paths(query.having)
      |> collect_order_paths(query.order_by)
      |> Kernel.++(query.group_by)

    associations =
      paths
      |> Enum.map(&association_path/1)
      |> Enum.reject(&(&1 == []))
      |> Enum.uniq()

    joins =
      associations
      |> Enum.sort_by(&length/1)
      |> Enum.map(&build_join/1)

    bindings = Enum.reduce(associations, %{[] => :root}, &put_binding/2)

    _ = resource

    {:ok, %{joins: joins, bindings: bindings}}
  end

  @doc """
  Returns the Ecto binding for a semantic path.
  """
  @spec binding_for_path(t(), [atom()]) :: atom()
  def binding_for_path(%{bindings: bindings}, path) do
    association_path = Enum.drop(path, -1)
    Map.get(bindings, association_path, :root)
  end

  defp collect_expression_paths(paths, nil), do: paths

  defp collect_expression_paths(paths, %Condition{path: path}) do
    [path | paths]
  end

  defp collect_expression_paths(paths, %And{conditions: conditions}) do
    Enum.reduce(conditions, paths, &collect_expression_paths(&2, &1))
  end

  defp collect_expression_paths(paths, %Or{conditions: conditions}) do
    Enum.reduce(conditions, paths, &collect_expression_paths(&2, &1))
  end

  defp collect_expression_paths(paths, %Not{expression: expression}) do
    collect_expression_paths(paths, expression)
  end

  defp collect_expression_paths(paths, _), do: paths

  defp collect_order_paths(paths, orders) do
    Enum.reduce(orders, paths, &collect_order_path/2)
  end

  defp collect_order_path(%Order{path: path}, paths), do: [path | paths]

  defp build_join(path) do
    parent_path = Enum.drop(path, -1)

    %{
      path: path,
      association: List.last(path),
      binding: binding_name(path),
      parent_binding: binding_name(parent_path)
    }
  end

  defp put_binding(path, acc), do: Map.put(acc, path, binding_name(path))

  defp association_path([_field]), do: []

  defp association_path(path) do
    Enum.drop(path, -1)
  end

  defp binding_name([]), do: :root

  defp binding_name(path) do
    path
    |> Enum.join("_")
    |> String.to_atom()
  end
end
