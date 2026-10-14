defmodule Swordfish.ToolTest do
  use ExUnit.Case

  alias Enum, as: PublicEnum
  alias Swordfish.Contract
  alias Swordfish.Discovery.AST
  alias Swordfish.Field
  alias Swordfish.Tool

  test "builds a tool from a contract" do
    contract =
      Contract.new(
        :search_filters,
        [
          %Field{name: :priority, type: :boolean},
          %Field{name: :status_options, type: :enum, source: ["today", "tomorrow"]}
        ],
        description: "Search filters"
      )

    assert {:ok, tool} = Tool.from_contract(contract)
    assert tool.name == "search_filters"
    assert tool.description == "Search filters"
    assert tool.handler == nil
    assert tool.input_schema.type == :object
    assert tool.input_schema.name == :search_filters
    assert tool.input_schema.description == "Search filters"
  end

  test "uses an empty description when the contract has none" do
    contract = Contract.new(:search_filters, [])

    assert {:ok, tool} = Tool.from_contract(contract)
    assert tool.description == ""
  end

  test "builds a tool with an entity field value type" do
    contract =
      Contract.new(:search_filters, [
        %Field{name: :providers, type: :entity, value_type: :integer, multiple?: true}
      ])

    assert {:ok, tool} = Tool.from_contract(contract)
    assert tool.input_schema.properties.providers.type == :array
    assert tool.input_schema.properties.providers.items == %{type: :integer}
  end

  test "returns schema errors from the contract" do
    contract = Contract.new(:search_filters, [%Field{name: :providers, type: :entity}])

    assert {:error, {:invalid_field, :providers, :entity_schema_requires_value_type}} =
             Tool.from_contract(contract)
  end

  test "resolves an MFA enum source into enum values" do
    tool =
      Tool.new("search", "", %{
        type: :object,
        properties: %{
          providers: %{type: :string, enum_source: [Swordfish.TestSupport.Providers, :names, []]}
        },
        required: []
      })

    assert {:ok, resolved_tool} = Tool.resolve(tool)

    assert resolved_tool.input_schema.properties.providers == %{
             type: :string,
             enum: ["Northwind"]
           }
  end

  test "resolves an enum source using runtime context" do
    tool =
      Tool.new("search", "", %{
        type: :object,
        properties: %{
          providers: %{
            type: :string,
            enum_source: [Swordfish.TestSupport.Providers, :list, [{:context, [:provider_id]}]]
          }
        },
        required: []
      })

    context = Swordfish.Context.new(%{provider_id: 42})

    assert {:ok, resolved_tool} = Tool.resolve(tool, context)

    assert resolved_tool.input_schema.properties.providers == %{
             type: :string,
             enum: [%{id: 42, name: "Northwind"}]
           }
  end

  test "resolves a function enum source into enum values" do
    resolver = fn -> quote do: [:one, :two] end

    tool =
      Tool.new("search", "", %{
        type: :object,
        properties: %{
          providers: %{type: :string, enum_source: {:function, resolver}}
        },
        required: []
      })

    assert {:ok, resolved_tool} = Tool.resolve(tool)
    assert resolved_tool.input_schema.properties.providers == %{type: :string, enum: [:one, :two]}
  end

  test "resolves a complex function enum source with an expanded module alias" do
    ast = quote do: [:two, :one] |> PublicEnum.sort()

    assert {:ok, {:function, resolver}} = AST.source(ast, __MODULE__)

    tool =
      Tool.new("search", "", %{
        type: :object,
        properties: %{
          providers: %{type: :string, enum_source: {:function, resolver}}
        },
        required: []
      })

    assert {:ok, resolved_tool} = Tool.resolve(tool)

    assert resolved_tool.input_schema.properties.providers == %{
             type: :string,
             enum: [:one, :two]
           }
  end

  test "resolves enum sources nested in array items" do
    tool =
      Tool.new("search", "", %{
        type: :object,
        properties: %{
          providers: %{
            type: :array,
            items: %{
              type: :string,
              enum_source: [Swordfish.TestSupport.Providers, :names, []]
            }
          }
        },
        required: []
      })

    assert {:ok, resolved_tool} = Tool.resolve(tool)

    assert resolved_tool.input_schema.properties.providers == %{
             type: :array,
             items: %{type: :string, enum: ["Northwind"]}
           }
  end

  test "returns an error when an enum resolver does not return a list" do
    tool =
      Tool.new("search", "", %{
        type: :object,
        properties: %{
          providers: %{type: :string, enum_source: [Map, :get, [%{value: :one}, :value]]}
        },
        required: []
      })

    assert {:error, {:invalid_property, :providers, {:invalid_enum_source_result, :one}}} =
             Tool.resolve(tool)
  end

  test "resolves entity metadata using a custom struct selection" do
    tool =
      Tool.new("search", "", %{
        type: :object,
        properties: %{
          providers: %{
            type: :array,
            items: %{type: :integer},
            entity_source: [Swordfish.TestSupport.Providers, :list_with_description, []],
            entity_struct: [:id, :description]
          }
        },
        required: []
      })

    assert {:ok, resolved_tool} = Tool.resolve(tool)

    assert resolved_tool.input_schema.properties.providers.entities == [
             %{id: 1, description: "Northwind"}
           ]
  end

  test "resolves entity metadata with only id as the required source attribute" do
    tool =
      Tool.new("search", "", %{
        type: :object,
        properties: %{
          providers: %{
            type: :array,
            items: %{type: :integer},
            entity_source: [Swordfish.TestSupport.Providers, :ids_only, []],
            entity_struct: [:id]
          }
        },
        required: []
      })

    assert {:ok, resolved_tool} = Tool.resolve(tool)

    assert resolved_tool.input_schema.properties.providers.entities == [%{id: 1}]
  end
end

defmodule Swordfish.ToolEntityTest do
  use ExUnit.Case

  alias Swordfish.Tool

  test "resolves entity options into id and name metadata" do
    source = [Swordfish.TestSupport.Providers, :list, []]

    tool =
      Tool.new("search", "", %{
        type: :object,
        properties: %{
          providers: %{
            type: :array,
            items: %{type: :integer},
            entity_source: source
          }
        },
        required: []
      })

    assert {:ok, resolved_tool} = Tool.resolve(tool)

    assert resolved_tool.input_schema.properties.providers == %{
             type: :array,
             items: %{type: :integer},
             entities: [%{id: 1, name: "Northwind"}]
           }
  end

  test "returns an error when an entity resolver does not return entity maps" do
    tool =
      Tool.new("search", "", %{
        type: :object,
        properties: %{
          providers: %{
            type: :array,
            items: %{type: :integer},
            entity_source: [Swordfish.TestSupport.Providers, :names, []]
          }
        },
        required: []
      })

    assert {:error, {:invalid_property, :providers, {:invalid_entity, "Northwind"}}} =
             Tool.resolve(tool)
  end
end
