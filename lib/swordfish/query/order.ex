defmodule Swordfish.Query.Order do
  @moduledoc "Ordering expression."

  @type t :: %__MODULE__{
          path: [atom()],
          direction: :asc | :desc
        }

  defstruct [
    :path,
    :direction
  ]
end
