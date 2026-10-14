defmodule Swordfish.Query.Executor do
  @moduledoc """
  Orchestrates decoding, policy application, validation and compilation.

  The executor does not call Repo. The caller remains responsible for the
  final database operation.
  """

  alias Swordfish.Policy
  alias Swordfish.Query.Decoder
  alias Swordfish.Query.Ecto
  alias Swordfish.Query.Validator
  alias Swordfish.Resource

  @doc """
  Converts structured LLM arguments into a safe Ecto query.

  Application policy is applied between decoding and validation.
  """
  @spec compile(Resource.t(), map(), Policy.t()) ::
          {:ok, Ecto.Query.t()} | {:error, term()}
  def compile(%Resource{} = resource, params, %Policy{} = policy) do
    resource
    |> decode(params)
    |> apply_policy(policy)
    |> validate(resource)
    |> compile_ecto(resource)
  end

  defp decode(resource, params) do
    Decoder.from_map(resource, params)
    |> case do
      {:ok, query} -> {:ok, query}
      {:error, reason} -> {:error, {:decode, reason}}
    end
  end

  defp apply_policy({:ok, query}, policy) do
    {:ok, Policy.apply(policy, query)}
  end

  defp apply_policy({:error, reason}, _policy), do: {:error, reason}

  defp validate({:ok, query}, resource) do
    Validator.validate(query, resource)
    |> case do
      {:ok, validated} -> {:ok, validated}
      {:error, reason} -> {:error, {:validation, reason}}
    end
  end

  defp validate({:error, reason}, _resource), do: {:error, reason}

  defp compile_ecto({:ok, query}, resource) do
    Ecto.compile(query, resource)
    |> case do
      {:ok, ecto_query} -> {:ok, ecto_query}
      {:error, reason} -> {:error, {:compile, reason}}
    end
  end

  defp compile_ecto({:error, reason}, _resource), do: {:error, reason}
end
