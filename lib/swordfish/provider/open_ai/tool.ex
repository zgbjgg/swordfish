defmodule Swordfish.Provider.OpenAI.Tool do
  @moduledoc "Translates a provider-neutral Swordfish tool into the OpenAI tool format."

  @doc "Converts a Swordfish tool into an OpenAI Responses API tool payload."
  @spec from(Swordfish.Tool.t()) :: map()
  def from(%Swordfish.Tool{} = tool) do
    %{
      "type" => "function",
      "name" => tool.name,
      "description" => tool.description,
      "parameters" => Swordfish.Provider.Schema.to_json(tool.input_schema)
    }
  end
end
