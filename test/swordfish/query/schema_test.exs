defmodule Swordfish.Query.SchemaTest do
  use ExUnit.Case

  alias Swordfish.Query.Schema
  alias Swordfish.Resource

  alias Swordfish.TestSchemas.Ticket

  test "generates a provider-neutral query tool schema" do
    resource = Resource.new(:ticket, Ticket, fields: [:status])
    tool = Schema.tool(resource)

    assert tool.name == "query_ticket"
    assert tool.input_schema["type"] == "object"
    assert tool.input_schema["properties"]["filters"]["type"] == "array"
  end
end
