defmodule Swordfish.Query.RelativeTime do
  @moduledoc """
  Represents a time relative to execution time.

  Example:

      %Swordfish.Query.RelativeTime{amount: -48, unit: :hour}
  """

  @type unit :: :second | :minute | :hour | :day | :week

  @type t :: %__MODULE__{
          amount: integer(),
          unit: unit()
        }

  defstruct [
    :amount,
    :unit
  ]
end
