defmodule Swordfish.Provider do
  @moduledoc "Behaviour implemented by LLM provider adapters."

  @callback chat(list(), list(Swordfish.Tool.t()), keyword()) ::
              {:ok, map()} | {:error, term()}
end
