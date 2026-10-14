defmodule Swordfish.Query.Schema do
  @moduledoc """
  Generates provider-neutral JSON Schema for Swordfish.Query.
  """

  alias Swordfish.Resource
  alias Swordfish.Query.Operator

  @doc """
  Builds a provider-neutral tool definition for a resource query.
  """
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
      "required" => ["filters", "limit"],
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
          "description" =>
            "Field path. Scalar fields must use a one-element path. " <>
              "Allowed scalar fields: #{allowed_fields(resource)}."
        },
        "operator" => %{
          "type" => "string",
          "enum" => Enum.map(Operator.all(), &Atom.to_string/1)
        },
        "value" => value_schema()
      },
      "required" => ["path", "operator", "value"],
      "additionalProperties" => false
    }
  end

  defp value_schema do
    %{
      "description" =>
        "Filter value. Use a scalar for comparison operators and an array for in or not_in.",
      "anyOf" => [
        %{"type" => "string"},
        %{"type" => "number"},
        %{"type" => "integer"},
        %{"type" => "boolean"},
        %{"type" => "null"},
        %{
          "type" => "array",
          "items" => %{
            "anyOf" => [
              %{"type" => "string"},
              %{"type" => "number"},
              %{"type" => "integer"},
              %{"type" => "boolean"},
              %{"type" => "null"}
            ]
          }
        }
      ]
    }
  end

  defp limit_schema do
    %{
      "type" => ["integer", "null"],
      "minimum" => 1,
      "maximum" => 1000
    }
  end

  defp allowed_fields(%Resource{fields: fields}) do
    Enum.map_join(fields, ", ", &Atom.to_string/1)
  end
end
