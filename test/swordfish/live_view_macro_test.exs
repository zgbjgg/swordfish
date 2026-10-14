defmodule Swordfish.LiveViewMacroTest do
  use ExUnit.Case

  alias Swordfish.TestSchemas.Ticket

  defmodule TestLive do
    use Swordfish.LiveView

    swordfish_resource :tickets, Ticket,
      fields: [:status, :priority]

    swordfish_action :clear_filters,
      description: "Clear all filters"

    swordfish_context :active_tab
    swordfish_context :current_filters
  end

  test "compiles resource declarations" do
    [resource] = TestLive.swordfish_resources()

    assert resource.name == :tickets
    assert resource.schema == Ticket
    assert resource.fields == [:status, :priority]
  end

  test "compiles action declarations" do
    [action] = TestLive.swordfish_actions()

    assert action.name == :clear_filters
    assert action.description == "Clear all filters"
  end

  test "compiles context declarations" do
    assert TestLive.swordfish_context_fields() == [
             :active_tab,
             :current_filters
           ]
  end

  test "builds an action capability from discovery" do
    [action] = Swordfish.TestSupport.CapabilityLive.swordfish_actions()

    assert action.name == :apply_filters
    assert action.capability.module == Swordfish.TestSupport.ApplicationInputs
    assert action.capability.name == :search
    assert action.capability.assigns == [
             providers: [
               type: :entity,
               multiple?: true,
               value_type: :integer,
               struct: [:id, :name]
             ]
           ]
  end

end
