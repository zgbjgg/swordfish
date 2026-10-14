defmodule Swordfish.ActionCapabilityTest do
  use ExUnit.Case

  alias Swordfish.Action.Capability
  alias Swordfish.Context
  alias Swordfish.TestSupport.ApplicationInputs

  test "resolves a discovered capability using runtime context" do
    capability =
      Capability.new(
        ApplicationInputs,
        :search,
        [
          providers: [
            type: :entity,
            multiple?: true,
            value_type: :integer,
            struct: [:id, :name]
          ]
        ]
      )
    context = Context.new(%{user: %{id: 42}})

    assert {:ok, resolved_tool} = Capability.resolve(capability, context)

    assert resolved_tool.input_schema.properties.providers.entities == [
             %{id: 42, name: "Northwind"}
           ]
  end
end
