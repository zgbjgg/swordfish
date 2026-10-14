defmodule Swordfish.ContextTest do
  use ExUnit.Case

  alias Swordfish.Context

  test "gets a nested value by path" do
    context = Context.new(%{user: %{account: %{id: 42}}})

    assert {:ok, 42} = Context.get_path(context, [:user, :account, :id])
  end

  test "returns an error for a missing path" do
    context = Context.new(%{user: %{id: 42}})

    assert :error = Context.get_path(context, [:user, :account, :id])
  end

  test "returns an error when a path traverses a non-map value" do
    context = Context.new(%{user: 42})

    assert :error = Context.get_path(context, [:user, :id])
  end
end
