defmodule Swordfish.TestSupport.ApplicationInputs do
  @doc "Returns the application entities available to the test capability."
  @spec providers(integer()) :: [map()]
  def providers(user_id) do
    [%{id: user_id, name: "Northwind"}]
  end

  @doc "Returns the fields exposed by the test application capability."
  @spec mount(term(), map()) :: {:ok, keyword()}
  def mount(_socket, user) do
    assigns = [
      providers: providers(user.id),
      enabled: false
    ]

    {:ok, assigns}
  end
end
