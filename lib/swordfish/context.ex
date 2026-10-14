defmodule Swordfish.Context do
  @moduledoc """
  Allowlisted runtime context exposed to an AI.

  Context is intentionally represented separately from the LiveView socket.
  """

  @type t :: %__MODULE__{
          values: map()
        }

  defstruct values: %{}

  @doc """
  Creates an empty Swordfish context.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Creates a context from a map of already-approved values.
  """
  @spec new(map()) :: t()
  def new(values) when is_map(values), do: %__MODULE__{values: values}

  @doc """
  Adds an approved value to the context.
  """
  @spec put(t(), atom(), term()) :: t()
  def put(%__MODULE__{values: values} = context, key, value) when is_atom(key) do
    %{context | values: Map.put(values, key, value)}
  end

  @doc """
  Returns an approved context value.
  """
  @spec get(t(), atom(), term()) :: term()
  def get(%__MODULE__{values: values}, key, default \\ nil) do
    Map.get(values, key, default)
  end

  @doc """
  Returns a nested approved context value by path.
  """
  @spec get_path(t() | term(), [atom()] | term()) :: {:ok, term()} | :error
  def get_path(value, path)

  def get_path(%__MODULE__{values: values}, path) when is_list(path) do
    get_path(values, path)
  end

  def get_path(value, []), do: {:ok, value}

  def get_path(value, [key | rest]) when is_map(value) and is_atom(key) do
    Map.fetch(value, key)
    |> case do
      {:ok, next_value} -> get_path(next_value, rest)
      :error -> :error
    end
  end

  def get_path(_value, _path), do: :error
end
