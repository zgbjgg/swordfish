defmodule Swordfish.IntentTest do
  use ExUnit.Case

  alias Swordfish.Contract
  alias Swordfish.Field
  alias Swordfish.Intent
  alias Swordfish.Tool

  defp tool do
    contract =
      Contract.new(
        :search_filters,
        [
          %Field{name: :priority, type: :boolean},
          %Field{name: :providers, type: :integer, multiple?: true},
          %Field{
            name: :status_options,
            type: :enum,
            multiple?: true,
            source: ["today", "tomorrow"]
          }
        ]
      )

    {:ok, tool} = Tool.from_contract(contract)
    tool
  end

  test "builds an intent from a normalized tool call" do
    tool_call = %{id: "call_1", name: "search_filters", arguments: %{priority: true}}

    assert {:ok, intent} = Intent.from_tool_call(tool_call)
    assert intent.id == "call_1"
    assert intent.name == "search_filters"
    assert intent.arguments == %{priority: true}
  end

  test "rejects an invalid tool call shape" do
    assert {:error, :invalid_tool_call} = Intent.from_tool_call(%{name: "search_filters"})
  end

  test "validates a tool call against the allowed tools" do
    intent = Intent.new("call_1", "search_filters", %{"priority" => true, "providers" => [12]})

    assert {:ok, ^intent} = Intent.validate(intent, [tool()])
  end

  test "rejects an unknown tool" do
    intent = Intent.new("call_1", "unknown", %{})

    assert {:error, {:unknown_tool, "unknown"}} = Intent.validate(intent, [tool()])
  end

  test "rejects an unknown argument" do
    intent = Intent.new("call_1", "search_filters", %{provider: 12})

    assert {:error, {:unknown_argument, [:arguments, :provider]}} =
             Intent.validate(intent, [tool()])
  end

  test "accepts atom and string argument keys" do
    atom_intent = Intent.new("call_1", "search_filters", %{priority: true, providers: [12]})

    string_intent =
      Intent.new("call_2", "search_filters", %{"priority" => true, "providers" => [12]})

    assert {:ok, ^atom_intent} = Intent.validate(atom_intent, [tool()])
    assert {:ok, ^string_intent} = Intent.validate(string_intent, [tool()])
  end

  test "rejects an invalid argument type" do
    intent = Intent.new("call_1", "search_filters", %{"priority" => "yes"})

    assert {:error, {:invalid_type, [:arguments, :priority], :boolean, "yes"}} =
             Intent.validate(intent, [tool()])
  end

  test "rejects an invalid enum value" do
    intent = Intent.new("call_1", "search_filters", %{"status_options" => ["next_week"]})

    assert {:error, {:invalid_enum_value, [:arguments, :status_options, 0], "next_week"}} =
             Intent.validate(intent, [tool()])
  end

  test "rejects a missing required argument" do
    contract =
      Contract.new(:search_filters, [%Field{name: :priority, type: :boolean, required?: true}])

    {:ok, tool} = Tool.from_contract(contract)
    intent = Intent.new("call_1", "search_filters", %{})

    assert {:error, {:missing_required, [:arguments, :priority]}} =
             Intent.validate(intent, [tool])
  end

  test "normalizes provider enum labels into their application values" do
    tool =
      Tool.new("search", "", %{
        type: :object,
        properties: %{
          category: %{type: :string, enum: [{"Legal Flatbed", :legal}, {"Van", :van}]}
        },
        required: []
      })

    intent = Intent.new("call_1", "search", %{"category" => "Legal Flatbed"})

    assert {:ok, normalized_intent} = Intent.validate(intent, [tool])
    assert normalized_intent.arguments == %{"category" => :legal}
  end

  test "normalizes provider atom enum values into application atoms" do
    tool =
      Tool.new("search", "", %{
        type: :object,
        properties: %{
          category: %{type: :string, enum: [:legal, :van]}
        },
        required: []
      })

    intent = Intent.new("call_1", "search", %{"category" => "legal"})

    assert {:ok, normalized_intent} = Intent.validate(intent, [tool])
    assert normalized_intent.arguments == %{"category" => :legal}
  end

  test "accepts nil for optional non-boolean arguments" do
    tool =
      Tool.new("search", "", %{
        type: :object,
        properties: %{
          origin: %{type: :string},
          include_related: %{type: :boolean}
        },
        required: []
      })

    intent =
      Intent.new("call_1", "search", %{
        "origin" => nil,
        "include_related" => false
      })

    assert {:ok, normalized_intent} = Intent.validate(intent, [tool])

    assert normalized_intent.arguments == %{
             "origin" => nil,
             "include_related" => false
           }
  end

  test "rejects nil for required arguments" do
    tool =
      Tool.new("search", "", %{
        type: :object,
        properties: %{origin: %{type: :string}},
        required: [:origin]
      })

    intent = Intent.new("call_1", "search", %{"origin" => nil})

    assert {:error, {:invalid_type, [:arguments, :origin], :non_nil, nil}} =
             Intent.validate(intent, [tool])
  end

  test "normalizes nil multiple enum arguments to an empty list" do
    tool =
      Tool.new("search", "", %{
        type: :object,
        properties: %{
          status_options: %{
            type: :array,
            items: %{type: :string, enum: ["today", "tomorrow"]},
            default: []
          }
        },
        required: []
      })

    intent = Intent.new("call-1", "search", %{"status_options" => nil})

    assert {:ok, validated} = Intent.validate(intent, [tool])
    assert validated.arguments == %{"status_options" => []}
  end

  test "normalizes nil multiple entity arguments to an empty list" do
    tool =
      Tool.new("search", "", %{
        type: :object,
        properties: %{
          providers: %{
            type: :array,
            items: %{type: :integer},
            entities: [%{id: 1, name: "Northwind"}],
            default: []
          }
        },
        required: []
      })

    intent = Intent.new("call-1", "search", %{"providers" => nil})

    assert {:ok, validated} = Intent.validate(intent, [tool])
    assert validated.arguments == %{"providers" => []}
  end

  test "preserves nil for non-option fields" do
    tool =
      Tool.new("search", "", %{
        type: :object,
        properties: %{origin: %{type: :string}},
        required: []
      })

    intent = Intent.new("call-1", "search", %{"origin" => nil})

    assert {:ok, validated} = Intent.validate(intent, [tool])
    assert validated.arguments == %{"origin" => nil}
  end
end
