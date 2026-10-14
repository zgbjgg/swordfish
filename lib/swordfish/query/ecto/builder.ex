defmodule Swordfish.Query.Ecto.Builder do
  @moduledoc """
  Runtime helpers for constructing Ecto query structures with dynamic bindings.

  Swordfish targets Ecto 3.6.x, where the query macros require compile-time
  atoms for named bindings in `as:` options. These helpers use Ecto's internal
  query builders at runtime so Swordfish can safely use allowlisted dynamic
  binding names.
  """

  alias Ecto.Query.{JoinExpr, QueryExpr}
  alias Ecto.Query.Builder.Join

  @doc """
  Applies an association join using a dynamic, allowlisted binding name.
  """
  @spec apply_association_join(Ecto.Query.t(), atom(), atom(), non_neg_integer()) ::
          Ecto.Query.t()
  def apply_association_join(%Ecto.Query{} = query, association, binding, parent_index)
      when is_atom(association) and is_atom(binding) and is_integer(parent_index) do
    join = %JoinExpr{
      assoc: {parent_index, association},
      as: binding,
      file: __ENV__.file,
      line: __ENV__.line,
      params: [],
      prefix: nil,
      qual: :inner,
      source: nil,
      hints: [],
      on: %QueryExpr{
        expr: true,
        params: [],
        file: __ENV__.file,
        line: __ENV__.line
      }
    }

    Join.apply(query, join, binding, length(query.joins) + 1)
  end
end
