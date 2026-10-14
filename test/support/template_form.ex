defmodule Swordfish.TestSupport.TemplateInputs do
  def mount(_socket) do
    assigns = [
      resources: Swordfish.TestSupport.Providers.simple_list(),
      internal_state: %{},
      derived_summary: [],
      selected_records: []
    ]

    {:ok, assigns}
  end
end
