defmodule Swordfish.Provider.SchemaTest do
  use ExUnit.Case

  alias Swordfish.Provider.Schema

  test "encodes datetime format using JSON Schema date-time" do
    assert Schema.to_json(%{type: :string, format: :date_time}) == %{
             "type" => "string",
             "format" => "date-time"
           }
  end
end
