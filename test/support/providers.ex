defmodule Swordfish.TestSupport.Providers do
  @moduledoc false

  @doc """
  Returns all test providers.
  """
  @spec list() :: [%{id: integer(), name: String.t()}]
  def list, do: [%{id: 1, name: "Northwind"}]

  @doc """
  Returns provider names for tests.
  """
  @spec names() :: [String.t()]
  def names, do: ["Northwind"]

  def list(user_id), do: [%{id: user_id, name: "Northwind"}]

  def simple_list, do: [%{id: 1, name: "Northwind"}]

  def simple_list_for_agents(user_id), do: [%{id: user_id, name: "Northwind"}]
  @doc false
  @spec list_with_description() :: [map()]
  def list_with_description, do: [%{id: 1, description: "Northwind", name: "Northwind"}]

  @doc false
  @spec ids_only() :: [map()]
  def ids_only, do: [%{id: 1}]
end
