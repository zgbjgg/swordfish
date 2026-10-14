defmodule Swordfish.Query.EctoTest do
  use ExUnit.Case

  alias Ecto.Query.JoinExpr
  alias Swordfish.Query.Builder, as: Q
  alias Swordfish.Query.Ecto
  alias Swordfish.Resource

  alias Swordfish.TestSchemas.Customer
  alias Swordfish.TestSchemas.Ticket

  defp resource do
    Resource.new(:ticket, Ticket,
      fields: [:status, :priority],
      associations: [
        customer: [
          schema: Customer,
          fields: [:name]
        ]
      ]
    )
  end

  test "compiles a root field condition" do
    query =
      Q.query(Ticket,
        where: Q.condition(:status, :eq, "open")
      )

    assert {:ok, ecto_query} = Ecto.compile(query, resource())

    assert ecto_query.from.source == {"tickets", Ticket}
  end

  test "plans an association join" do
    query =
      Q.query(Ticket,
        where: Q.condition([:customer, :name], :eq, "Pato")
      )

    assert {:ok, ecto_query} = Ecto.compile(query, resource())

    join = List.first(ecto_query.joins)

    assert length(ecto_query.joins) == 1

    assert %JoinExpr{
             assoc: {0, :customer},
             as: :customer,
             qual: :inner
           } = join

    assert ecto_query.aliases[:customer] == 1
  end

  test "compiles nested AND/OR expressions" do
    query =
      Q.query(Ticket,
        where:
          Q.and_([
            Q.condition(:status, :eq, "open"),
            Q.or_([
              Q.condition(:priority, :eq, 1),
              Q.condition([:customer, :name], :eq, "Pato")
            ])
          ])
      )

    assert {:ok, ecto_query} = Ecto.compile(query, resource())
    assert length(ecto_query.joins) == 1
  end

  test "compiles root order and group expressions" do
    query =
      Q.query(Ticket,
        order_by: [Q.order(:priority, :desc)],
        group_by: [[:status]]
      )

    assert {:ok, ecto_query} = Ecto.compile(query, resource())
    assert ecto_query.order_bys != []
    assert ecto_query.group_bys != []
  end

  test "compiles association order and group expressions" do
    query =
      Q.query(Ticket,
        order_by: [Q.order([:customer, :name], :asc)],
        group_by: [[:customer, :name]]
      )

    assert {:ok, ecto_query} = Ecto.compile(query, resource())
    assert length(ecto_query.joins) == 1
    assert ecto_query.order_bys != []
    assert ecto_query.group_bys != []
  end
end
