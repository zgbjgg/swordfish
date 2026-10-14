defmodule Swordfish.Query.Value do
  @moduledoc "Helpers for validating values used by the query AST."

  alias Swordfish.Query.RelativeTime

  @doc "Validates a value against an Ecto field type."
  @spec valid_for_type?(term(), term()) :: boolean()
  def valid_for_type?(value, type) do
    type
    |> value_type_valid?(value)
  end

  defp value_type_valid?(:string, value), do: is_binary(value) or match?(%RelativeTime{}, value)
  defp value_type_valid?(:integer, value), do: is_integer(value)
  defp value_type_valid?(:float, value), do: is_float(value) or is_integer(value)
  defp value_type_valid?(:boolean, value), do: is_boolean(value)
  defp value_type_valid?(:date, value), do: match?(%Date{}, value)
  defp value_type_valid?(:time, value), do: match?(%Time{}, value)
  defp value_type_valid?(:naive_datetime, value), do: match?(%NaiveDateTime{}, value)
  defp value_type_valid?(:utc_datetime, value), do: match?(%DateTime{}, value)
  defp value_type_valid?(:id, value), do: is_integer(value) or is_binary(value)
  defp value_type_valid?({:parameterized, _}, _value), do: true
  defp value_type_valid?({:array, inner}, value) when is_list(value) do
    Enum.all?(value, &valid_for_type?(&1, inner))
  end
  defp value_type_valid?(nil, _value), do: false
  defp value_type_valid?(_type, _value), do: true
end
