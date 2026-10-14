defmodule Swordfish.Provider.OpenAIToolTest do
  use ExUnit.Case

  alias Swordfish.Provider.OpenAI.Tool
  alias Swordfish.Tool, as: SwordfishTool

  test "translates a Swordfish tool to the OpenAI format" do
    tool = SwordfishTool.new("query_tickets", "Query tickets", %{"type" => "object"})

    assert %{
             "type" => "function",
             "name" => "query_tickets",
             "description" => "Query tickets",
             "parameters" => %{"type" => "object"}
           } = Tool.from(tool)
  end

  test "converts provider-neutral enum values into JSON-compatible values" do
    tool =
      SwordfishTool.new("search", "Search", %{
        type: :object,
        properties: %{
          category: %{type: :string, enum: [{"Legal Flatbed", :legal}, {"Van", :van}]}
        },
        required: []
      })

    assert %{
             "parameters" => %{
               "type" => "object",
               "properties" => %{
                 "category" => %{
                   "type" => ["string", "null"],
                   "enum" => ["Legal Flatbed", "Van", nil]
                 }
               },
               "required" => ["category"],
               "additionalProperties" => false
             }
           } = Tool.from(tool)
  end

  test "projects resolved entity options into provider parameters" do
    tool =
      SwordfishTool.new("search", "Search", %{
        type: :object,
        properties: %{
          providers: %{
            type: :array,
            items: %{type: :integer},
            entities: [%{id: 1, name: "Acme Provider"}],
            entity_struct: [:id, :name],
            default: []
          }
        },
        required: []
      })

    assert %{
             "parameters" => %{
               "properties" => %{
                 "providers" => %{
                   "type" => ["array", "null"],
                   "default" => [],
                   "items" => %{
                     "type" => "integer",
                     "enum" => [1],
                     "description" => "Available values: 1 = Acme Provider"
                   }
                 }
               }
             }
           } = Tool.from(tool)
  end

  test "removes Swordfish metadata from provider parameters" do
    tool =
      SwordfishTool.new("search", "Search", %{
        type: :object,
        name: :search,
        description: nil,
        properties: %{
          providers: %{
            type: :array,
            items: %{type: :integer},
            entities: [%{id: 1, description: "Northwind"}],
            entity_struct: [:id, :description]
          },
          origin: %{type: :string, description: "Origin city"}
        },
        required: []
      })

    assert %{
             "parameters" => %{
               "type" => "object",
               "properties" => %{
                 "providers" => %{
                   "type" => ["array", "null"],
                   "items" => %{
                     "type" => "integer",
                     "description" => "Available values: 1 = Northwind",
                     "enum" => [1]
                   }
                 },
                 "origin" => %{
                   "type" => ["string", "null"],
                   "description" => "Origin city"
                 }
               },
               "required" => required,
               "additionalProperties" => false
             }
           } = Tool.from(tool)

    assert Enum.sort(required) == Enum.sort(["providers", "origin"])
  end

  test "removes empty enum schemas from provider parameters" do
    tool =
      SwordfishTool.new("search", "Search", %{
        type: :object,
        properties: %{
          sort_by: %{type: :string, enum: []},
          origin: %{type: :string}
        },
        required: []
      })

    assert %{
             "parameters" => %{
               "type" => "object",
               "properties" => %{"origin" => %{"type" => ["string", "null"]}},
               "required" => ["origin"],
               "additionalProperties" => false
             }
           } = Tool.from(tool)
  end
  test "makes optional non-boolean properties nullable for strict providers" do
    tool =
      SwordfishTool.new("search", "Search", %{
        type: :object,
        properties: %{
          origin: %{type: :string},
          amount_range: %{type: :string, enum: [{"0 - 400", :zero_to_four_hundred}]},
          include_related: %{type: :boolean}
        },
        required: []
      })

    assert %{
             "parameters" => %{
               "type" => "object",
               "properties" => %{
                 "origin" => %{"type" => ["string", "null"]},
                 "amount_range" => %{
                   "type" => ["string", "null"],
                   "enum" => ["0 - 400", nil]
                 },
                 "include_related" => %{"type" => "boolean"}
               },
               "required" => required,
               "additionalProperties" => false
             }
           } = Tool.from(tool)

    assert Enum.sort(required) == Enum.sort(["origin", "amount_range", "include_related"])
  end

end

