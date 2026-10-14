defmodule Swordfish.Query.Condition do
  @moduledoc """
  A single query condition.

  A path can contain fields and associations, for example:

      [:status]
      [:customer, :name]
      [:customer, :account_manager, :name]
  """

  @type t :: %__MODULE__{
          path: [atom()],
          operator: atom(),
          value: term()
        }

  defstruct [
    :path,
    :operator,
    :value
  ]
end
