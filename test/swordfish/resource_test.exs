defmodule Swordfish.ResourceTest do
  use ExUnit.Case

  alias Swordfish.Resource
  alias Swordfish.Query.Builder, as: Q
  alias Swordfish.Query.Validator

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

  test "allows exposed fields" do
    query = Q.query(Ticket, where: Q.condition(:status, :eq, "open"))

    assert {:ok, ^query} = Validator.validate(query, resource())
  end

  test "allows exposed association fields" do
    query =
      Q.query(Ticket,
        where: Q.condition([:customer, :name], :eq, "Pato")
      )

    assert {:ok, ^query} = Validator.validate(query, resource())
  end

  test "rejects fields that are not exposed" do
    query = Q.query(Ticket, where: Q.condition(:customer_id, :eq, 123))

    assert {:error, {:field_not_allowed, :ticket, :customer_id}} =
             Validator.validate(query, resource())
  end

  test "rejects fields from an exposed association that are not exposed" do
    query =
      Q.query(Ticket,
        where: Q.condition([:customer, :secret], :eq, "x")
      )

    assert {:error, {:field_not_allowed, :customer, :secret}} =
             Validator.validate(query, resource())
  end

  test "validates query parts without building invalid captures" do
    query =
      Q.query(Ticket,
        where: Q.condition(:status, :eq, "open"),
        order_by: [Q.order(:priority, :desc)],
        limit: 20,
        offset: 0
      )

    assert {:ok, ^query} = Validator.validate(query, resource())
  end

  test "rejects invalid operators" do
    query = Q.query(Ticket, where: Q.condition(:status, :wat, "open"))

    assert {:error, {:invalid_operator, :wat}} = Validator.validate(query, resource())
  end

  test "rejects invalid resource" do
    query = Q.query(Customer, where: Q.condition(:name, :eq, "Pato"))

    assert {:error, :resource_mismatch} = Validator.validate(query, resource())
  end
end
