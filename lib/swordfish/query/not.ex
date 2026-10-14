defmodule Swordfish.Query.Not do
  @moduledoc "Logical NOT expression."

  @type t :: %__MODULE__{
          expression: Swordfish.Query.expression()
        }

  defstruct [:expression]
end
