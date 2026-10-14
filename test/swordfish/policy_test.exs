defmodule Swordfish.PolicyTest do
  use ExUnit.Case

  alias Swordfish.Policy
  alias Swordfish.Query.Builder, as: Q
  alias Swordfish.Query.Constraint

  alias Swordfish.TestSchemas.Ticket

  test "applies an application-owned constraint" do
    query =
      Q.query(Ticket,
        where: Q.condition(:status, :eq, :open)
      )

    policy =
      Policy.new()
      |> Policy.add_constraint(&Constraint.where(&1, Q.condition(:organization_id, :eq, 42)))

    result = Policy.apply(policy, query)

    assert %Swordfish.Query.And{} = result.where
    assert length(result.where.conditions) == 2
  end
end
