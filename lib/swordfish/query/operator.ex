defmodule Swordfish.Query.Operator do
  @moduledoc "Operators supported by the Swordfish.Query AST."

  @operators [
    :eq,
    :neq,
    :gt,
    :gte,
    :lt,
    :lte,
    :in,
    :not_in,
    :contains,
    :starts_with,
    :ends_with,
    :is_nil,
    :is_not_nil
  ]

  @type t ::
          :eq
          | :neq
          | :gt
          | :gte
          | :lt
          | :lte
          | :in
          | :not_in
          | :contains
          | :starts_with
          | :ends_with
          | :is_nil
          | :is_not_nil

  @doc """
  Returns whether an operator is supported.
  """
  @spec valid?(atom()) :: boolean()
  def valid?(operator), do: operator in @operators

  @doc """
  Returns all supported operators.
  """
  @spec all() :: [t()]
  def all, do: @operators
end
