defmodule Swordfish.LiveView.Toolbox do
  @moduledoc """
  Builds the AI-visible toolbox for a LiveView runtime.

  A toolbox contains only explicitly registered resources and actions.
  """

  alias Swordfish.LiveView
  alias Swordfish.Query.Schema

  @doc """
  Builds the list of query tools exposed by the LiveView.
  """
  @spec query_tools(LiveView.t()) :: [map()]
  def query_tools(%LiveView{resources: resources}) do
    resources
    |> Map.values()
    |> Enum.map(&Schema.tool/1)
  end

  @doc """
  Builds the list of action tools exposed by the LiveView.
  """
  @spec action_tools(LiveView.t()) :: [Swordfish.Action.t()]
  def action_tools(%LiveView{actions: actions}) do
    Map.values(actions)
  end

  @doc """
  Builds the complete toolbox exposed by the LiveView.
  """
  @spec tools(LiveView.t()) :: %{queries: [map()], actions: [Swordfish.Action.t()]}
  def tools(%LiveView{} = runtime) do
    %{
      queries: query_tools(runtime),
      actions: action_tools(runtime)
    }
  end
end
