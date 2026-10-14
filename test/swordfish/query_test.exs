defmodule Swordfish.QueryTest do
  use ExUnit.Case

  alias Swordfish.Query
  alias Swordfish.Query.Builder, as: Q

  alias Swordfish.TestSchemas.Ticket

  test "builds a simple query" do
    query =
      Q.query(Ticket,
        where: Q.condition(:status, :eq, :open),
        limit: 20
      )

    assert %Query{resource: Ticket, limit: 20} = query
    assert query.where.path == [:status]
    assert query.where.operator == :eq
    assert query.where.value == :open
  end

  test "builds nested boolean expressions" do
    query =
      Q.query(Ticket,
        where:
          Q.and_([
            Q.condition(:status, :eq, :open),
            Q.condition(:priority, :eq, 1),
            Q.or_([
              Q.condition([:customer, :name], :eq, "Pato"),
              Q.condition([:customer, :name], :eq, "Gato")
            ])
          ])
      )

    assert query.resource == Ticket
    assert length(query.where.conditions) == 3

    [status, priority, customers] = query.where.conditions

    assert status.path == [:status]
    assert priority.path == [:priority]
    assert %Swordfish.Query.Or{} = customers
    assert length(customers.conditions) == 2
  end

  test "builds ordering" do
    query =
      Q.query(Ticket,
        order_by: [Q.order(:priority, :desc)],
        limit: 10,
        offset: 20
      )

    assert [%Swordfish.Query.Order{path: [:priority], direction: :desc}] = query.order_by
    assert query.limit == 10
    assert query.offset == 20
  end
end
