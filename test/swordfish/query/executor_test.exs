defmodule Swordfish.Query.ExecutorTest do
  use ExUnit.Case

  alias Swordfish.Policy
  alias Swordfish.Query.Executor
  alias Swordfish.Resource

  alias Swordfish.TestSchemas.Customer
  alias Swordfish.TestSchemas.Ticket

  defp resource do
    Resource.new(:ticket, Ticket,
      fields: [:status, :organization_id],
      associations: [
        customer: [
          schema: Customer,
          fields: [:name]
        ]
      ]
    )
  end

  test "applies policy before compilation" do
    params = %{
      "filters" => [
        %{
          "path" => ["status"],
          "operator" => "eq",
          "value" => "open"
        }
      ]
    }

    policy =
      Policy.new()
      |> Policy.add_constraint(
        &Swordfish.Query.Constraint.where(
          &1,
          Swordfish.Query.Builder.condition(:organization_id, :eq, 42)
        )
      )

    assert {:ok, ecto_query} = Executor.compile(resource(), params, policy)
    assert ecto_query.from.source == {"tickets", Ticket}
  end
end
