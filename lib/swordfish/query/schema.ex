defmodule Swordfish.Query.Schema do
  @moduledoc "Generates provider-neutral JSON Schema for Swordfish.Query."

  alias Swordfish.Resource
  alias Swordfish.Query.Operator

  @doc "Builds a provider-neutral tool definition for a resource query."
  @spec tool(Resource.t(), keyword()) :: map()
  def tool(%Resource{} = resource, opts \\ []) do
    %{
      name: Keyword.get(opts, :name, "query_#{resource.name}"),
      description: Keyword.get(opts, :description, "Query #{resource.name}"),
      input_schema: input_schema(resource)
    }
  end

  defp input_schema(resource) do
    %{
      "type" => "object",
      "properties" => %{
        "filters" => filters_schema(resource),
        "limit" => limit_schema()
      },
      "additionalProperties" => false
    }
  end

  defp filters_schema(resource) do
    %{
      "type" => "array",
      "description" => "Filters to apply to the query.",
      "items" => filter_schema(resource)
    }
  end

  defp filter_schema(resource) do
    %{
      "type" => "object",
      "properties" => %{
        "path" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" => "Semantic path, for example [\"customer\", \"name\"]."
        },
        "operator" => %{
          "type" => "string",
          "enum" => Operator.all() |> Enum.map(&Atom.to_string/1)
        },
        "value" => %{"description" => "Filter value."}
      },
      "required" => ["path", "operator"],
      "additionalProperties" => false,
      "x-resource" => Atom.to_string(resource.name)
    }
  end

  defp limit_schema do
    %{
      "type" => "integer",
      "minimum" => 1,
      "maximum" => 1000
    }
  end
end
