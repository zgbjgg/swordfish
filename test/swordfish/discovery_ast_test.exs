defmodule Swordfish.DiscoveryASTTest do
  use ExUnit.Case

  alias Swordfish.Discovery
  alias Swordfish.Discovery.AST

  test "discovers a remote function as an MFA source" do
    ast = quote do: Swordfish.TestSupport.Providers.list()

    assert {:ok, [Swordfish.TestSupport.Providers, :list, []]} =
             AST.source(ast, __MODULE__)
  end

  test "discovers a remote function with arguments" do
    ast = quote do: Swordfish.TestSupport.Providers.list(user.id)

    assert {:ok, [Swordfish.TestSupport.Providers, :list, [{:context, [:user, :id]}]]} =
             AST.source(ast, __MODULE__)
  end

  test "discovers a static list" do
    ast = quote do
      [
        %{id: "manual", name: "Manual"},
        %{id: "mobile_app", name: "Mobile App"}
      ]
    end

    assert {:ok, [
             %{id: "manual", name: "Manual"},
             %{id: "mobile_app", name: "Mobile App"}
           ]} = AST.source(ast, __MODULE__)
  end

  test "discovers a field from a remote function" do
    ast = quote do: Swordfish.TestSupport.Providers.list()

    assert {:ok, field} = Discovery.discover_field(:items, ast, __MODULE__)
    assert field.name == :items
    assert field.type == :fn
    assert field.multiple? == false
    assert field.source == [Swordfish.TestSupport.Providers, :list, []]
  end

  test "discovers a static field as an enum" do
    ast = quote do: ["yesterday", "today", "tomorrow"]

    assert {:ok, field} = Discovery.discover_field(:status_options, ast, __MODULE__)
    assert field.name == :status_options
    assert field.type == :enum
    assert field.multiple? == true
    assert field.source == ["yesterday", "today", "tomorrow"]
  end


  test "expands grouped module aliases inside complex function resolvers" do
    ast = quote do: [:two, :one] |> Providers.list()

    assert {:ok, {:function, resolver}} = AST.source(ast, SwordfishDiscoveryASTGroupedAliasFixture)

    expression = resolver.()

    assert Macro.to_string(expression) =~ "[:two, :one] |> Swordfish.TestSupport.Providers.list()"
  end

  test "expands grouped module aliases inside MFA sources" do
    ast = quote do: Providers.list()

    assert {:ok, [Swordfish.TestSupport.Providers, :list, []]} =
             AST.source(ast, SwordfishDiscoveryASTGroupedAliasFixture)
  end

  test "discovers local calls using the current module as the MFA module" do
    ast = quote do: get_entity_list(user.id)

    assert {:ok, [__MODULE__, :get_entity_list, _arguments]} =
             AST.source(ast, __MODULE__)
  end
end

defmodule SwordfishDiscoveryASTContextTest do
  use ExUnit.Case

  alias Swordfish.Discovery.AST

  test "discovers a bare runtime variable as context" do
    ast = quote do: use_extended_list?

    assert {:ok, {:context, [:use_extended_list?]}} = AST.source(ast, __MODULE__)
  end
end


defmodule SwordfishDiscoveryASTGroupedAliasFixture do
  alias Swordfish.TestSupport.{Providers, OtherProvider}

  def providers, do: Providers.list()
end
