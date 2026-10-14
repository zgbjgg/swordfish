defmodule Swordfish.Action.Capability do
  @moduledoc """
  Discovered application capability attached to a Swordfish action.
  """

  alias Swordfish.Context
  alias Swordfish.Tool

  @type t :: %__MODULE__{
          module: module(),
          name: atom(),
          assigns: keyword()
        }

  defstruct [:module, :name, assigns: []]

  @doc "Creates an action capability from a discovery declaration."
  @spec new(module(), atom(), keyword()) :: t()
  def new(module, name, assigns) when is_atom(module) and is_atom(name) and is_list(assigns) do
    %__MODULE__{module: module, name: name, assigns: assigns}
  end

  @doc "Discovers and resolves an action capability using approved runtime context."
  @spec resolve(t(), Context.t()) :: {:ok, Tool.t()} | {:error, term()}
  def resolve(%__MODULE__{} = capability, %Context{} = context) do
    capability
    |> discover_contract()
    |> resolve_discovered_contract(context)
  end

  defp discover_contract(%__MODULE__{} = capability) do
    Swordfish.Discovery.discover_contract(
      capability.module,
      capability.name,
      assigns: capability.assigns
    )
  end

  defp resolve_discovered_contract({:ok, contract}, context) do
    Tool.from_contract(contract)
    |> case do
      {:ok, tool} -> Tool.resolve(tool, context)
      {:error, reason} -> {:error, {:tool, reason}}
    end
  end

  defp resolve_discovered_contract({:error, reason}, _context), do: {:error, {:discovery, reason}}
end
