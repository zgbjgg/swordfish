defmodule Swordfish.Query.And do
  @moduledoc "Logical AND expression."

  @type t :: %__MODULE__{
          conditions: [Swordfish.Query.expression()]
        }

  defstruct conditions: []
end
