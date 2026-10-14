defmodule Swordfish.Query.Builder do
  @moduledoc "Convenience functions for constructing Swordfish.Query ASTs."

  alias Swordfish.Query
  alias Swordfish.Query.{Condition, And, Or, Not, Order}

  @doc "Builds a query AST for a resource."
  @spec query(module(), keyword()) :: Query.t()
  def query(resource, opts \\ []) do
    struct!(Query, Keyword.put(opts, :resource, resource))
  end

  @doc "Builds a query condition."
  @spec condition([atom()] | atom(), atom(), term()) :: Condition.t()
  def condition(path, operator, value) do
    %Condition{path: List.wrap(path), operator: operator, value: value}
  end

  @doc "Builds an AND expression."
  @spec and_([Query.expression()]) :: And.t()
  def and_(conditions), do: %And{conditions: conditions}

  @doc "Builds an OR expression."
  @spec or_([Query.expression()]) :: Or.t()
  def or_(conditions), do: %Or{conditions: conditions}

  @doc "Builds a NOT expression."
  @spec not_(Query.expression()) :: Not.t()
  def not_(expression), do: %Not{expression: expression}

  @doc "Builds an order expression."
  @spec order([atom()] | atom(), :asc | :desc) :: Order.t()
  def order(path, direction \\ :asc) do
    %Order{path: List.wrap(path), direction: direction}
  end
end
