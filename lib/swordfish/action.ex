defmodule Swordfish.Action do
  @moduledoc """
  Declarative description of an action exposed to an AI.

  The action describes intent and input shape. The application remains
  responsible for executing the action.
  """

  @type t :: %__MODULE__{
          name: atom(),
          description: String.t(),
          input_schema: map(),
          handler: function() | nil,
          capability: Swordfish.Action.Capability.t() | nil
        }

  defstruct [
    :name,
    :description,
    :input_schema,
    :handler,
    :capability
  ]

  @doc """
  Creates a Swordfish action.
  """
  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) when is_atom(name) do
    %__MODULE__{
      name: name,
      description: Keyword.get(opts, :description, ""),
      input_schema: Keyword.get(opts, :input_schema, empty_schema()),
      handler: Keyword.get(opts, :handler),
      capability: Keyword.get(opts, :capability)
    }
  end

  defp empty_schema do
    %{
      "type" => "object",
      "properties" => %{},
      "additionalProperties" => false
    }
  end
end
