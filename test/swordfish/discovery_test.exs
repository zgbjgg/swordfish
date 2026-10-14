defmodule SwordfishDiscoveryTest do
  use ExUnit.Case

  alias Swordfish.Discovery

  def mount(_socket) do
    assigns = [
      providers: Swordfish.TestSupport.Providers.list(),
      tracking_sources: [
        %{id: "manual", name: "Manual"},
        %{id: "mobile_app", name: "Mobile App"}
      ],
      enabled: false
    ]

    {:ok, assigns}
  end

  test "discovers fields from the module source" do
    assert {:ok, fields} = Discovery.discover(__MODULE__)

    assert [
             %{name: :providers, type: :fn, multiple?: false},
             %{name: :tracking_sources, type: :enum, multiple?: true},
             %{name: :enabled, type: :boolean, multiple?: false}
           ] = fields
  end

  test "preserves discovered sources" do
    assert {:ok, fields} = Discovery.discover(__MODULE__)

    providers = Enum.find(fields, &(&1.name == :providers))
    tracking_sources = Enum.find(fields, &(&1.name == :tracking_sources))

    assert providers.source == [Swordfish.TestSupport.Providers, :list, []]

    assert tracking_sources.source == [
             %{id: "manual", name: "Manual"},
             %{id: "mobile_app", name: "Mobile App"}
           ]
  end

end


defmodule SwordfishDiscoveryDateInputTest do
  use ExUnit.Case

  alias Swordfish.Discovery

  test "discovers date and datetime Phoenix form inputs" do
    assert {:ok, fields} = Discovery.discover(Swordfish.TestSupport.DateInputForm)

    start_date = Enum.find(fields, &(&1.name == :start_date))
    start_at = Enum.find(fields, &(&1.name == :start_at))

    assert start_date.type == :date
    assert start_at.type == :datetime
  end
end


defmodule SwordfishDiscoverySourceTest do
  use ExUnit.Case

  alias Swordfish.Discovery

  def mount(_socket, user) do
    assigns = [
      providers: Swordfish.TestSupport.Providers.list(user.id),
      status_options: ["yesterday", "today", "tomorrow"]
    ]

    {:ok, assigns}
  end

  test "discovers a dynamic source with runtime arguments" do
    assert {:ok, fields} = Discovery.discover(__MODULE__)
    providers = Enum.find(fields, &(&1.name == :providers))

    assert providers.type == :fn
    assert providers.multiple? == false

    assert providers.source == [
             Swordfish.TestSupport.Providers,
             :list,
             [{:context, [:user, :id]}]
           ]
  end

  test "discovers static options as an enum" do
    assert {:ok, fields} = Discovery.discover(__MODULE__)
    status_options = Enum.find(fields, &(&1.name == :status_options))

    assert status_options.type == :enum
    assert status_options.multiple? == true
  end
end


defmodule SwordfishDiscoveryResolverTest do
  use ExUnit.Case

  alias Swordfish.Resolver

  test "executes a discovered MFA source" do
    assert {:ok, [%{id: 1, name: "Northwind"}]} =
             Resolver.resolve([Swordfish.TestSupport.Providers, :list, []])
  end
end


defmodule SwordfishDiscoveryContractTest do
  use ExUnit.Case

  alias Swordfish.Discovery

  def mount(_socket) do
    assigns = [
      providers: Swordfish.TestSupport.Providers.list(),
      enabled: false
    ]

    {:ok, assigns}
  end

  test "discovers a contract from module fields" do
    assert {:ok, contract} = Discovery.discover_contract(__MODULE__, :search_contract)

    assert contract.name == :search_contract
    assert Enum.map(contract.fields, & &1.name) == [:providers, :enabled]
  end

  test "preserves discovered field definitions in the contract" do
    assert {:ok, contract} = Discovery.discover_contract(__MODULE__, :search_contract)

    providers = Enum.find(contract.fields, &(&1.name == :providers))
    enabled = Enum.find(contract.fields, &(&1.name == :enabled))

    assert providers.source == [Swordfish.TestSupport.Providers, :list, []]
    assert providers.type == :fn
    assert enabled.type == :boolean
  end
end


defmodule SwordfishDiscoveryEntityTest do
  use ExUnit.Case

  alias Swordfish.Discovery

  def get_entity_list(nil, _), do: Swordfish.TestSupport.Providers.simple_list()
  def get_entity_list(false, _), do: Swordfish.TestSupport.Providers.simple_list()
  def get_entity_list(true, user_id),
    do: Swordfish.TestSupport.Providers.simple_list_for_agents(user_id)

  def mount(_socket) do
    assigns = [
      items: get_entity_list(false, 42)
    ]

    {:ok, assigns}
  end

  test "explicit entity metadata preserves a public local resolver MFA" do
    assert {:ok, [field]} =
             Discovery.discover(
               __MODULE__,
               assigns: [items: [type: :entity, value_type: :integer, multiple?: true, struct: [:id, :name]]]
             )

    assert field.type == :entity
    assert field.multiple? == true
    assert field.value_type == :integer
    assert field.struct == [:id, :name]

    assert field.source == [
             __MODULE__,
             :get_entity_list,
             [false, 42]
           ]
  end

  test "preserves the public entity resolver MFA in the contract" do
    assert {:ok, contract} =
             Discovery.discover_contract(
               __MODULE__,
               :search_filters,
               assigns: [items: [type: :entity, value_type: :integer, multiple?: true, struct: [:id, :name]]]
             )

    field = Enum.find(contract.fields, &(&1.name == :items))

    assert field.source == [
             __MODULE__,
             :get_entity_list,
             [false, 42]
           ]

    assert field.type == :entity
    assert field.value_type == :integer
    assert field.struct == [:id, :name]
    assert field.multiple? == true
  end

end


defmodule SwordfishDiscoveryTemplateTest do
  use ExUnit.Case

  alias Swordfish.Discovery

  test "discovers public inputs from a sibling HEEx template" do
    assert {:ok, fields} = Discovery.discover(Swordfish.TestSupport.TemplateInputs)

    assert Enum.map(fields, & &1.name) |> Enum.sort() ==
             [:enabled, :record_id, :record_type, :resources]

    enabled = Enum.find(fields, &(&1.name == :enabled))
    record_id = Enum.find(fields, &(&1.name == :record_id))
    resources = Enum.find(fields, &(&1.name == :resources))
    record_type = Enum.find(fields, &(&1.name == :record_type))

    assert enabled.type == :boolean
    assert record_id.type == :string
    assert resources.type == :enum
    assert resources.multiple? == true
    assert record_type.type == :string
  end

  test "does not expose component state that is absent from the template" do
    assert {:ok, fields} = Discovery.discover(Swordfish.TestSupport.TemplateInputs)

    names = Enum.map(fields, & &1.name)

    refute :internal_state in names
    refute :derived_summary in names
    refute :selected_records in names
  end
end


defmodule SwordfishDiscoveryLeexTemplateTest do
  use ExUnit.Case

  alias Swordfish.Discovery

  def mount(_socket) do
    assigns = [
      category: "ftl",
      include_related: false,
      selected_providers: []
    ]

    {:ok, assigns}
  end

  test "discovers Phoenix.HTML helpers from a sibling LEEx template" do
    assert {:ok, fields} = Discovery.discover(Swordfish.TestSupport.TemplateLeexForm)

    names = Enum.map(fields, & &1.name)

    assert :category in names
    assert :include_related in names
    assert :external_only in names
    assert :origin in names
    refute :providers in names

    category = Enum.find(fields, &(&1.name == :category))
    include_related = Enum.find(fields, &(&1.name == :include_related))
    external_only = Enum.find(fields, &(&1.name == :external_only))
    assert category.type == :enum
    assert category.options == {:assign, :category_segment}
    assert include_related.type == :boolean
    assert external_only.type == :enum
    assert external_only.options == ["yes", "no"]
  end

  test "discovers explicitly requested assigns without coupling to template components" do
    assert {:ok, fields} =
             Discovery.discover(
               Swordfish.TestSupport.TemplateLeexForm,
               assigns: [providers: [type: :entity, value_type: :integer, multiple?: true, struct: [:id, :name]]]
             )

    providers = Enum.find(fields, &(&1.name == :providers))

    assert providers.type == :entity
    assert providers.multiple? == true
    assert providers.value_type == :integer
    assert providers.struct == [:id, :name]
    assert providers.source == [Swordfish.TestSupport.Providers, :list, []]
  end

  test "merges explicit assign metadata into an existing template field without duplicating it" do
    assert {:ok, fields} =
             Discovery.discover(
               Swordfish.TestSupport.TemplateLeexForm,
               assigns: [origin: [type: :string, required?: true]]
             )

    origin_fields = Enum.filter(fields, &(&1.name == :origin))

    assert [%{name: :origin, type: :string, required?: true, source: {:template, :origin}}] =
             origin_fields
  end

  test "discovers explicit assigns through the contract API" do
    assert {:ok, contract} =
             Discovery.discover_contract(
               Swordfish.TestSupport.TemplateLeexForm,
               :search_contract,
               assigns: [providers: [type: :entity, value_type: :integer, multiple?: true, struct: [:id, :description]]]
             )

    providers = Enum.find(contract.fields, &(&1.name == :providers))
    assert providers.type == :entity
    assert providers.multiple? == true
    assert providers.value_type == :integer
    assert providers.struct == [:id, :description]
  end

  test "ignores live components when their assigns are not explicitly requested" do
    assert {:ok, fields} = Discovery.discover(Swordfish.TestSupport.TemplateLeexForm)

    refute Enum.any?(fields, &(&1.name == :providers))
  end

  test "extracts static select options as enum values" do
    assert {:ok, fields} = Discovery.discover(Swordfish.TestSupport.TemplateLeexForm)

    field = Enum.find(fields, &(&1.name == :order_at))

    assert field.type == :enum
    assert field.multiple? == false
    assert field.options == [:desc, :asc]
  end

  test "uses direct assign values as enum options" do
    assert {:ok, fields} = Discovery.discover(Swordfish.TestSupport.TemplateLeexForm)

    field = Enum.find(fields, &(&1.name == :static_choice))

    assert field.type == :enum
    assert field.options == [:one, :two]
  end

  test "uses assign function sources as dynamic enum resolvers" do
    assert {:ok, fields} = Discovery.discover(Swordfish.TestSupport.TemplateLeexForm)

    field = Enum.find(fields, &(&1.name == :dynamic_choice))

    assert field.type == :enum
    assert field.options ==
             {:resolver, [Swordfish.TestSupport.Providers, :list, []]}
  end

  test "represents assign pipelines as function resolvers" do
    assert {:ok, fields} = Discovery.discover(Swordfish.TestSupport.TemplateLeexForm)

    field = Enum.find(fields, &(&1.name == :pipeline_choice))

    assert field.type == :enum
    assert {:resolver, {:function, resolver}} = field.options
    assert is_function(resolver, 0)
    expression = resolver.()
    assert Macro.to_string(expression) =~ "Swordfish.TestSupport.Providers.list()"
    assert Macro.to_string(expression) =~ "Enum.map"
  end

  test "represents local assign pipelines as function resolvers" do
    assert {:ok, fields} = Discovery.discover(Swordfish.TestSupport.TemplateLeexForm)

    field = Enum.find(fields, &(&1.name == :local_pipeline_choice))

    assert field.type == :enum
    assert {:resolver, {:function, resolver}} = field.options
    assert is_function(resolver, 0)
    expression = resolver.()
    assert Macro.to_string(expression) =~ "Swordfish.TestSupport.TemplateLeexForm.render_options([:one, :two])"
  end

end
