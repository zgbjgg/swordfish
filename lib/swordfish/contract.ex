defmodule Swordfish.Contract do
  @moduledoc """
  Provider-independent representation of an application capability contract.
  """

  alias Swordfish.Field

  @type t :: %__MODULE__{
          name: atom(),
          description: binary() | nil,
          fields: [Field.t()]
        }

  defstruct [
    :name,
    :description,
    fields: []
  ]

  @doc """
  Builds a contract from a name and discovered fields.
  """
  @spec new(atom(), [Field.t()]) :: t()
  def new(name, fields) when is_atom(name) and is_list(fields) do
    %__MODULE__{name: name, fields: fields}
  end

  @doc """
  Builds a contract with optional metadata.
  """
  @spec new(atom(), [Field.t()], keyword()) :: t()
  def new(name, fields, options) when is_atom(name) and is_list(fields) and is_list(options) do
    %__MODULE__{
      name: name,
      description: Keyword.get(options, :description),
      fields: fields
    }
  end
end
