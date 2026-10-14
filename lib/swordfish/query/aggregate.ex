defmodule Swordfish.Query.Aggregate do
  @moduledoc "Aggregate expression."

  @type function_name :: :count | :sum | :avg | :min | :max

  @type t :: %__MODULE__{
          function: function_name(),
          path: [atom()],
          as: atom()
        }

  defstruct [
    :function,
    :path,
    :as
  ]
end
