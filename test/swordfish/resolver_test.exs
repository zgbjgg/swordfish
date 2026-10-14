defmodule Swordfish.ResolverTest do
  use ExUnit.Case

  alias Swordfish.Context
  alias Swordfish.Resolver

  test "executes a discovered MFA source" do
    assert {:ok, [%{id: 1, name: "Northwind"}]} =
             Resolver.resolve([Swordfish.TestSupport.Providers, :list, []])
  end

  test "executes a discovered MFA source with literal arguments" do
    assert {:ok, [%{id: 42, name: "Northwind"}]} =
             Resolver.resolve([Swordfish.TestSupport.Providers, :list, [42]])
  end

  test "resolves runtime context references before execution" do
    context = Context.new(%{user: %{id: 42}})
    source = [Swordfish.TestSupport.Providers, :list, [{:context, [:user, :id]}]]

    assert {:ok, [%{id: 42, name: "Northwind"}]} = Resolver.resolve(source, context)
  end

  test "resolves nested runtime context references" do
    context = Context.new(%{user: %{account: %{id: 99}}})
    source = [Swordfish.TestSupport.Providers, :list, [{:context, [:user, :account, :id]}]]

    assert {:ok, [%{id: 99, name: "Northwind"}]} = Resolver.resolve(source, context)
  end

  test "returns an error when a runtime context reference is missing" do
    context = Context.new(%{user: %{id: 42}})
    source = [Swordfish.TestSupport.Providers, :list, [{:context, [:user, :account_id]}]]

    assert {:error, {:missing_context, [:user, :account_id]}} = Resolver.resolve(source, context)
  end

  test "rejects invalid resolver sources" do
    assert {:error, :invalid_resolver_source} = Resolver.resolve(:invalid)
  end
end


defmodule SwordfishResolverFunctionTest do
  use ExUnit.Case

  alias Swordfish.Context
  alias Swordfish.Resolver

  test "executes a discovered function expression" do
    expression =
      quote do
        Swordfish.TestSupport.Providers.list()
        |> Enum.map(&Map.get(&1, :name))
      end

    resolver = fn -> expression end

    assert {:ok, ["Northwind"]} = Resolver.resolve({:function, resolver})
  end

  test "executes a discovered function expression with runtime context" do
    expression =
      quote do
        values |> Enum.sort()
      end
      |> replace_values_context()

    context = Context.new(%{values: [3, 1, 2]})

    resolver = fn -> expression end

    assert {:ok, [1, 2, 3]} = Resolver.resolve({:function, resolver}, context)
  end

  defp replace_values_context(expression) do
    Macro.prewalk(expression, &replace_values_context_node/1)
  end

  defp replace_values_context_node({:values, _metadata, _context}), do: {:context, [:values]}
  defp replace_values_context_node(node), do: node
end
