defmodule Swordfish.TestSupport.CapabilityLive do
  use Swordfish.LiveView

  swordfish_action :apply_filters,
    description: "Apply filters",
    discovery: [
      module: Swordfish.TestSupport.ApplicationInputs,
      name: :search,
      assigns: [
        providers: [
          type: :entity,
          multiple?: true,
          value_type: :integer,
          struct: [:id, :name]
        ]
      ]
    ]
end
