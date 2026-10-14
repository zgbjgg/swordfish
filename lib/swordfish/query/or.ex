defmodule Swordfish.Query.Or do
  @moduledoc "Logical OR expression."

  @type t :: %__MODULE__{
          conditions: [Swordfish.Query.expression()]
        }

  defstruct conditions: []
end
