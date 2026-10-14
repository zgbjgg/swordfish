defmodule Swordfish.RuntimeTest do
  use ExUnit.Case

  alias Swordfish.Context
  alias Swordfish.LiveView
  alias Swordfish.Policy
  alias Swordfish.Runtime
  alias Swordfish.Runtime.Result

  alias Swordfish.TestSchemas.Ticket

  defmodule Provider do
    @behaviour Swordfish.Provider

    @impl true
    def chat(_messages, _tools, _opts) do
      {:ok,
       %{
         "type" => "tool_call",
         "tool_call" => %{
           "id" => "call-1",
           "name" => "query_tickets",
           "arguments" => %{
             "filters" => [
               %{"path" => ["status"], "operator" => "eq", "value" => "open"}
             ],
             "limit" => 20
           }
         }
       }}
    end
  end

  defmodule ActionProvider do
    @behaviour Swordfish.Provider

    @impl true
    def chat(_messages, _tools, _opts) do
      {:ok,
       %{
         type: :tool_call,
         tool_call: %{
           id: "call-2",
           name: "clear_filters",
           arguments: %{}
         }
       }}
    end
  end

  test "has_related a query tool call through the query executor" do
    live_view =
      LiveView.new()
      |> LiveView.add_resource(
        :tickets,
        Swordfish.Resource.new(:tickets, Ticket, fields: [:status, :priority])
      )
      |> LiveView.put_context(Context.new(%{active_tab: :open}))

    runtime = Runtime.new(live_view, Provider, Policy.new())

    assert {:ok, %Result{status: :query, ecto_query: ecto_query, query: query}} =
             Runtime.run(runtime, "show me the open tickets")

    assert query.where.path == [:status]
    assert ecto_query != nil
  end

  test "returns an action intent without executing application code" do
    action = Swordfish.Action.new(:clear_filters, description: "Clear filters")

    live_view = LiveView.new() |> LiveView.add_action(action)
    runtime = Runtime.new(live_view, ActionProvider, Policy.new())

    assert {:ok, %Result{status: :action, action: ^action, arguments: %{}}} =
             Runtime.run(runtime, "clear the filters")
  end
end
