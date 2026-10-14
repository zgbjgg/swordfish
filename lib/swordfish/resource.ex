defmodule Swordfish.Resource do
  @moduledoc """
  Explicit allowlist describing the part of an Ecto schema exposed to Swordfish.
  """

  @type association :: %{
          name: atom(),
          module: module(),
          fields: [atom()],
          associations: keyword()
        }

  @type t :: %__MODULE__{
          name: atom(),
          schema: module(),
          fields: [atom()],
          associations: %{optional(atom()) => association()},
          max_depth: pos_integer()
        }

  defstruct [
    :name,
    :schema,
    fields: [],
    associations: %{},
    max_depth: 2
  ]

  @doc """
  Creates a Swordfish resource from an explicit allowlist.
  """
  @spec new(atom(), module(), keyword()) :: t()
  def new(name, schema, opts \\ []) when is_atom(name) and is_atom(schema) do
    %__MODULE__{
      name: name,
      schema: schema,
      fields: Keyword.get(opts, :fields, []),
      associations: normalize_associations(Keyword.get(opts, :associations, [])),
      max_depth: Keyword.get(opts, :max_depth, 2)
    }
  end

  @doc """
  Creates a resource using Ecto schema introspection for fields.
  """
  @spec from_schema(atom(), module(), keyword()) :: t()
  def from_schema(name, schema, opts \\ []) do
    opts
    |> schema_fields(schema)
    |> schema_associations()
    |> Keyword.merge(name: name)
    |> build_resource(schema)
  end

  @doc """
  Returns whether a field is exposed by the resource.
  """
  @spec field_allowed?(t(), atom()) :: boolean()
  def field_allowed?(%__MODULE__{fields: fields}, field), do: field in fields

  @doc """
  Returns metadata for an exposed association.
  """
  @spec association(t(), atom()) :: association() | nil
  def association(%__MODULE__{associations: associations}, name) do
    Map.get(associations, name)
  end

  @doc """
  Returns the Ecto type of a schema field.
  """
  @spec field_type(t(), atom()) :: term() | nil
  def field_type(%__MODULE__{schema: schema}, field) do
    Code.ensure_loaded(schema)
    |> case do
      {:module, ^schema} -> schema_field_type(schema, field)
      {:error, _reason} -> nil
    end
  end

  defp schema_fields(opts, schema) do
    fields = Keyword.get(opts, :fields, schema.__schema__(:fields))
    Keyword.put(opts, :fields, fields)
  end

  defp schema_associations(opts) do
    Keyword.put_new(opts, :associations, [])
  end

  defp build_resource(opts, schema) do
    new(Keyword.fetch!(opts, :name), schema, opts)
  end

  defp schema_field_type(schema, field) do
    case field in schema.__schema__(:fields) do
      true -> schema.__schema__(:type, field)
      false -> nil
    end
  end

  defp normalize_associations(associations) when is_list(associations) do
    Enum.into(associations, %{}, &normalize_association/1)
  end

  defp normalize_associations(associations) when is_map(associations), do: associations

  defp normalize_association({name, opts}) when is_list(opts) do
    {name,
     %{
       name: name,
       module: Keyword.fetch!(opts, :schema),
       fields: Keyword.get(opts, :fields, []),
       associations: Keyword.get(opts, :associations, [])
     }}
  end

  defp normalize_association({name, schema}) when is_atom(schema) do
    {name, %{name: name, module: schema, fields: [], associations: []}}
  end
end
