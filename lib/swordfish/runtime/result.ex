defmodule Swordfish.Runtime.Result do
  @moduledoc "Structured result returned by Swordfish.Runtime."

  @type status :: :responded | :query | :action | :error

  @type t :: %__MODULE__{
          status: status(),
          message: String.t() | nil,
          query: Swordfish.Query.t() | nil,
          ecto_query: Ecto.Query.t() | nil,
          action: Swordfish.Action.t() | nil,
          arguments: map(),
          tool_call_id: String.t() | nil,
          error: term() | nil
        }

  defstruct [
    :status,
    :message,
    :query,
    :ecto_query,
    :action,
    :arguments,
    :tool_call_id,
    :error
  ]

  @doc """
  Creates a final assistant response result.
  """
  @spec responded(String.t()) :: t()
  def responded(message) when is_binary(message) do
    %__MODULE__{status: :responded, message: message}
  end

  @doc """
  Creates a query result.
  """
  @spec query(Swordfish.Query.t(), Ecto.Query.t(), String.t() | nil) :: t()
  def query(query, ecto_query, tool_call_id) do
    %__MODULE__{status: :query, query: query, ecto_query: ecto_query, tool_call_id: tool_call_id}
  end

  @doc """
  Creates an action intent result.
  """
  @spec action(Swordfish.Action.t(), map(), String.t() | nil) :: t()
  def action(action, arguments, tool_call_id) do
    %__MODULE__{
      status: :action,
      action: action,
      arguments: arguments,
      tool_call_id: tool_call_id
    }
  end

  @doc """
  Creates an error result.
  """
  @spec error(term()) :: t()
  def error(reason), do: %__MODULE__{status: :error, error: reason}
end
