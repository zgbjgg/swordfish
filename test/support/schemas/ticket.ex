defmodule Swordfish.TestSchemas.Ticket do
  use Ecto.Schema

  schema "tickets" do
    field(:status, :string)
    field(:priority, :integer)
    field(:organization_id, :integer)

    belongs_to(:customer, Swordfish.TestSchemas.Customer)
  end
end
