defmodule Swordfish.TestSupport.TemplateLeexForm do
  def render_options(options), do: options

  def mount(_socket) do
    assigns = [
      providers: Swordfish.TestSupport.Providers.list(),
      category: "ftl",
      include_related: false,
      selected_providers: [],
      static_options: [{"One", :one}, {"Two", :two}],
      dynamic_options: Swordfish.TestSupport.Providers.list(),
      pipeline_options: Swordfish.TestSupport.Providers.list() |> Enum.map(&Map.get(&1, :name)),
      local_pipeline_options: [:one, :two] |> render_options()
    ]

    {:ok, assigns}
  end
end
