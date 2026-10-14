defmodule Swordfish.Query.ValueTest do
  use ExUnit.Case

  alias Swordfish.Query.Value

  test "validates common primitive types" do
    assert Value.valid_for_type?("open", :string)
    assert Value.valid_for_type?(1, :integer)
    assert Value.valid_for_type?(true, :boolean)
    refute Value.valid_for_type?("1", :integer)
  end
end
