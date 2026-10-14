defmodule Swordfish.Query do
  @moduledoc """
  Declarative query AST for Swordfish-powered applications.

  Swordfish.Query represents what the user wants to retrieve. It does not execute
  queries and does not depend on Ecto.
  """

  alias Swordfish.Query.{Condition, And, Or, Not, Order}

  @type path :: [atom()]

  @type expression ::
          Condition.t()
          | And.t()
          | Or.t()
          | Not.t()

  @type t :: %__MODULE__{
          resource: module(),
          select: [term()] | nil,
          where: expression() | nil,
          having: expression() | nil,
          order_by: [Order.t()],
          group_by: [path()],
          limit: pos_integer() | nil,
          offset: non_neg_integer() | nil
        }

  defstruct [
    :resource,
    :select,
    :where,
    :having,
    order_by: [],
    group_by: [],
    limit: nil,
    offset: nil
  ]

  @doc """
  Creates an empty query for a resource.
  """
  @spec new(module()) :: t()
  def new(resource) when is_atom(resource) do
    %__MODULE__{resource: resource}
  end
end
