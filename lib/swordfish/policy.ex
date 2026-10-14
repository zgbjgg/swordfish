defmodule Swordfish.Policy do
  @moduledoc """
  Defines application-owned constraints that are injected into a query.

  Policies are applied after decoding the LLM request and before compilation.
  The LLM cannot remove or override them.
  """

  @type constraint :: (Swordfish.Query.t() -> Swordfish.Query.t())

  @type t :: %__MODULE__{
          constraints: [constraint()]
        }

  defstruct constraints: []

  @doc "Creates an empty policy."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      constraints: Keyword.get(opts, :constraints, [])
    }
  end

  @doc "Adds an application-owned query constraint to a policy."
  @spec add_constraint(t(), constraint()) :: t()
  def add_constraint(%__MODULE__{constraints: constraints} = policy, constraint)
      when is_function(constraint, 1) do
    %{policy | constraints: constraints ++ [constraint]}
  end

  @doc "Applies all policy constraints to a query."
  @spec apply(t(), Swordfish.Query.t()) :: Swordfish.Query.t()
  def apply(%__MODULE__{constraints: constraints}, query) do
    Enum.reduce(constraints, query, &apply_constraint/2)
  end

  defp apply_constraint(constraint, query), do: constraint.(query)
end
