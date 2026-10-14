defmodule Swordfish.TestSupport.DateInputForm do
  def mount(_socket) do
    assigns = [start_date: nil, start_at: nil]
    {:ok, assigns}
  end
end
