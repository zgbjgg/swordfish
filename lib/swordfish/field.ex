defmodule Swordfish.Field do
  @moduledoc """
  Provider-independent representation of an application input field.
  """

  @type type ::
          :string | :integer | :boolean | :date | :datetime | :enum | :entity | :fn | :unknown
  @type source :: term()

  @type t :: %__MODULE__{
          name: atom(),
          type: type(),
          value_type: atom() | term() | nil,
          struct: [atom()] | nil,
          description: binary() | nil,
          multiple?: boolean(),
          required?: boolean(),
          source: source(),
          options: source() | nil
        }

  defstruct [
    :name,
    :type,
    :value_type,
    :struct,
    :description,
    multiple?: false,
    required?: false,
    source: nil,
    options: nil
  ]
end
