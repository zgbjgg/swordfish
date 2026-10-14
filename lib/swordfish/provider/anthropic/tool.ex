defmodule Swordfish.Provider.Anthropic.Tool do
  @moduledoc "Translates a provider-neutral Swordfish tool into the Anthropic tool format."

  @doc "Converts a Swordfish tool into an Anthropic Messages API tool payload."
  @spec from(Swordfish.Tool.t()) :: map()
  def from(%Swordfish.Tool{} = tool) do
    %{
      "name" => tool.name,
      "description" => tool.description,
      "input_schema" => Swordfish.Provider.Schema.to_json(tool.input_schema)
    }
  end
end
