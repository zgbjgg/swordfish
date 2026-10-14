defmodule Swordfish.LiveViewTest do
  use ExUnit.Case

  alias Swordfish.Action
  alias Swordfish.Context
  alias Swordfish.LiveView
  alias Swordfish.LiveView.Toolbox
  alias Swordfish.Resource

  alias Swordfish.TestSchemas.Ticket

  test "registers resources and actions" do
    resource = Resource.new(:ticket, Ticket, fields: [:status])
    action = Action.new(:clear_filters, description: "Clear all filters")

    runtime =
      LiveView.new()
      |> LiveView.add_resource(:ticket, resource)
      |> LiveView.add_action(action)

    assert LiveView.resource(runtime, :ticket) == resource
    assert LiveView.action(runtime, :clear_filters) == action
  end

  test "stores approved context" do
    context =
      Context.new()
      |> Context.put(:active_tab, :open)
      |> Context.put(:current_filters, %{status: :open})

    runtime =
      LiveView.new()
      |> LiveView.put_context(context)

    assert Context.get(runtime.context, :active_tab) == :open
    assert Context.get(runtime.context, :current_filters) == %{status: :open}
  end

  test "builds a toolbox from registered definitions" do
    resource = Resource.new(:ticket, Ticket, fields: [:status])
    action = Action.new(:clear_filters, description: "Clear all filters")

    runtime =
      LiveView.new()
      |> LiveView.add_resource(:ticket, resource)
      |> LiveView.add_action(action)

    toolbox = Toolbox.tools(runtime)

    assert length(toolbox.queries) == 1
    assert length(toolbox.actions) == 1
  end
end
