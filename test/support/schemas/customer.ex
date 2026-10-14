defmodule Swordfish.TestSchemas.Customer do
  use Ecto.Schema

  schema "customers" do
    field(:name, :string)
    field(:secret, :string)
  end
end
