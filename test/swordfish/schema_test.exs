defmodule Swordfish.SchemaTest do
  use ExUnit.Case

  alias Swordfish.Contract
  alias Swordfish.Field
  alias Swordfish.Schema

  test "builds an object schema from a contract" do
    contract =
      Contract.new(
        :search_filters,
        [
          %Field{name: :priority, type: :boolean},
          %Field{
            name: :status_options,
            type: :enum,
            multiple?: true,
            source: ["today", "tomorrow"]
          }
        ],
        description: "Search filters"
      )

    assert {:ok, schema} = Schema.from_contract(contract)

    assert schema == %{
             type: :object,
             name: :search_filters,
             description: "Search filters",
             properties: %{
               priority: %{type: :boolean, description: nil},
               status_options: %{
                 type: :array,
                 items: %{type: :string, enum: ["today", "tomorrow"]},
                 default: [],
                 description: nil
               }
             },
             required: []
           }
  end

  test "builds a required field schema" do
    field = %Field{
      name: :limit,
      type: :integer,
      required?: true,
      description: "Maximum number of results"
    }

    assert {:ok, schema} = Schema.field(field)
    assert schema == %{type: :integer, description: "Maximum number of results"}
  end

  test "builds an array schema for multiple primitive fields" do
    field = %Field{name: :tags, type: :string, multiple?: true}

    assert {:ok, schema} = Schema.field(field)
    assert schema == %{type: :array, items: %{type: :string}, description: nil}
  end

  test "builds an enum schema from static values" do
    field = %Field{name: :status_options, type: :enum, source: ["today", "tomorrow"]}

    assert {:ok, schema} = Schema.field(field)
    assert schema == %{type: :string, enum: ["today", "tomorrow"], description: nil}
  end

  test "builds a schema from dynamic enum options" do
    field = %Field{
      name: :record_type,
      type: :enum,
      options: {:resolver, [Swordfish.TestSupport.Providers, :list, []]}
    }

    assert {:ok, schema} = Schema.field(field)

    assert schema == %{
             type: :string,
             enum_source: [Swordfish.TestSupport.Providers, :list, []],
             description: nil
           }
  end

  test "builds an array schema from dynamic enum options" do
    field = %Field{
      name: :record_types,
      type: :enum,
      multiple?: true,
      options: {:resolver, [Swordfish.TestSupport.Providers, :list, []]}
    }

    assert {:ok, schema} = Schema.field(field)

    assert schema == %{
             type: :array,
             items: %{
               type: :string,
               enum_source: [Swordfish.TestSupport.Providers, :list, []]
             },
             default: [],
             description: nil
           }
  end

  test "requires explicit metadata for entity fields" do
    field = %Field{name: :providers, type: :entity, multiple?: true}

    assert {:error, :entity_schema_requires_value_type} = Schema.field(field)
  end

  test "builds an integer schema for a single entity" do
    field = %Field{name: :provider, type: :entity, value_type: :integer}

    assert {:ok, schema} = Schema.field(field)
    assert schema == %{type: :integer, entity_struct: [:id, :name], description: nil}
  end

  test "builds an integer array schema for multiple entities" do
    field = %Field{name: :providers, type: :entity, value_type: :integer, multiple?: true}

    assert {:ok, schema} = Schema.field(field)

    assert schema == %{
             type: :array,
             items: %{type: :integer},
             entity_struct: [:id, :name],
             default: [],
             description: nil
           }
  end

  test "builds a string schema for a single entity" do
    field = %Field{name: :provider, type: :entity, value_type: :string}

    assert {:ok, schema} = Schema.field(field)
    assert schema == %{type: :string, entity_struct: [:id, :name], description: nil}
  end

  test "requires explicit metadata for function sources" do
    field = %Field{name: :providers, type: :fn}

    assert {:error, :function_source_requires_field_type} = Schema.field(field)
  end

  test "builds a datetime schema" do
    field = %Field{name: :start_at, type: :datetime}

    assert {:ok, schema} = Schema.field(field)
    assert schema == %{type: :string, format: :date_time, description: nil}
  end
end

defmodule Swordfish.SchemaEntitySourceTest do
  use ExUnit.Case

  alias Swordfish.Field
  alias Swordfish.Schema

  test "preserves an entity resolver source for a single entity" do
    source = [Swordfish.TestSupport.Providers, :list, []]
    field = %Field{name: :provider, type: :entity, value_type: :integer, source: source}

    assert {:ok, schema} = Schema.field(field)

    assert schema == %{
             type: :integer,
             entity_source: source,
             entity_struct: [:id, :name],
             description: nil
           }
  end

  test "preserves an entity resolver source for multiple entities" do
    source = [Swordfish.TestSupport.Providers, :list, []]

    field = %Field{
      name: :providers,
      type: :entity,
      value_type: :integer,
      multiple?: true,
      source: source
    }

    assert {:ok, schema} = Schema.field(field)

    assert schema == %{
             type: :array,
             items: %{type: :integer},
             entity_source: source,
             entity_struct: [:id, :name],
             default: [],
             description: nil
           }
  end
end
