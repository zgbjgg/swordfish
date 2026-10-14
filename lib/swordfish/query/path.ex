defmodule Swordfish.Query.Path do
  @moduledoc "Resolves semantic paths against a Swordfish.Resource."

  alias Swordfish.Resource

  @doc """
  Resolves a semantic path against a resource allowlist.
  """
  @spec resolve(Resource.t(), [atom()]) :: {:ok, map()} | {:error, term()}
  def resolve(%Resource{} = resource, path) when is_list(path) do
    do_resolve(resource, path, [], 0)
  end

  defp do_resolve(_resource, [], _associations, _depth), do: {:error, :empty_path}

  defp do_resolve(resource, [field], associations, _depth) do
    if Resource.field_allowed?(resource, field) do
      {:ok,
       %{
         path: [field],
         field: field,
         type: Resource.field_type(resource, field),
         schema: resource.schema,
         associations: Enum.reverse(associations)
       }}
    else
      {:error, {:field_not_allowed, resource.name, field}}
    end
  end

  defp do_resolve(resource, [association_name | rest], associations, depth) do
    if depth >= resource.max_depth do
      {:error, :max_depth_exceeded}
    else
      Resource.association(resource, association_name)
      |> case do
        nil ->
          {:error, {:association_not_allowed, resource.name, association_name}}

        association ->
          next_resource =
            Resource.new(
              association_name,
              association.module,
              fields: association.fields,
              associations: association.associations,
              max_depth: resource.max_depth
            )

          do_resolve(
            next_resource,
            rest,
            [association.module | associations],
            depth + 1
          )
      end
    end
  end
end
