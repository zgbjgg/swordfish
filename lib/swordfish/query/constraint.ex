defmodule Swordfish.Query.Constraint do
  @moduledoc """
  Helpers for expressing application-owned query constraints.

  Constraints are regular Swordfish expressions, but are created by the
  application rather than by the LLM.
  """

  alias Swordfish.Query.Builder, as: Q

  @doc """
  Adds a condition to a query using AND semantics.
  """
  @spec where(Swordfish.Query.t(), Swordfish.Query.expression()) :: Swordfish.Query.t()
  def where(query, expression) do
    %{query | where: append_and(query.where, expression)}
  end

  defp append_and(nil, expression), do: expression

  defp append_and(existing, expression) do
    Q.and_([existing, expression])
  end
end
