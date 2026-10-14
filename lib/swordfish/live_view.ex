defmodule Swordfish.LiveView do
  @moduledoc """
  Phoenix LiveView integration for Swordfish.

  The macros register declarative AI resources, actions and context fields.
  Runtime state is stored in ordinary assigns so Swordfish does not need to
  expose the Phoenix socket to the LLM.
  """

  @doc """
  Imports the Swordfish LiveView DSL and registers its compile-time declarations.
  """
  defmacro __using__(_opts) do
    quote do
      import Swordfish.LiveView,
        only: [
          swordfish_resource: 2,
          swordfish_resource: 3,
          swordfish_action: 1,
          swordfish_action: 2,
          swordfish_context: 1,
          swordfish_context: 2
        ]

      @before_compile Swordfish.LiveView
      Module.register_attribute(__MODULE__, :swordfish_resources, accumulate: true)
      Module.register_attribute(__MODULE__, :swordfish_actions, accumulate: true)
      Module.register_attribute(__MODULE__, :swordfish_context, accumulate: true)
    end
  end

  @doc """
  Registers an Ecto resource as visible to Swordfish.
  """
  defmacro swordfish_resource(name, schema, opts \\ []) do
    quote do
      @swordfish_resources {
        unquote(name),
        unquote(schema),
        unquote(opts)
      }
    end
  end

  @doc """
  Registers an AI action as visible to Swordfish.
  """
  defmacro swordfish_action(name, opts \\ []) do
    quote do
      @swordfish_actions {
        unquote(name),
        unquote(opts)
      }
    end
  end

  @doc """
  Registers a LiveView context field as visible to Swordfish.
  """
  defmacro swordfish_context(name, opts \\ []) do
    quote do
      @swordfish_context {
        unquote(name),
        unquote(opts)
      }
    end
  end

  @doc """
  Generates the compiled Swordfish declarations for the LiveView module.
  """
  defmacro __before_compile__(env) do
    resources = Module.get_attribute(env.module, :swordfish_resources) |> Enum.reverse()
    actions = Module.get_attribute(env.module, :swordfish_actions) |> Enum.reverse()
    actions = Enum.map(actions, &compile_action(&1))
    context = Module.get_attribute(env.module, :swordfish_context) |> Enum.reverse()

    quote do
      @doc """
      Returns the Swordfish resource declarations for this LiveView.
      """
      @spec swordfish_resources() :: [Swordfish.Resource.t()]
      def swordfish_resources do
        unquote(Macro.escape(resources))
        |> Enum.map(&build_resource/1)
      end

      @doc """
      Returns the Swordfish action declarations for this LiveView.
      """
      @spec swordfish_actions() :: [Swordfish.Action.t()]
      def swordfish_actions do
        unquote(Macro.escape(actions))
      end

      @doc """
      Returns the Swordfish context declarations for this LiveView.
      """
      @spec swordfish_context_fields() :: [atom()]
      def swordfish_context_fields do
        unquote(Macro.escape(context))
        |> Enum.map(&context_name/1)
      end

      defp build_resource({name, schema, opts}) do
        Swordfish.Resource.from_schema(name, schema, opts)
      end

      defp context_name({name, _opts}), do: name
    end
  end

  @type t :: %__MODULE__{
          resources: %{optional(atom()) => Swordfish.Resource.t()},
          actions: %{optional(atom()) => Swordfish.Action.t()},
          context: Swordfish.Context.t()
        }

  defstruct resources: %{},
            actions: %{},
            context: %Swordfish.Context{}

  @doc """
  Creates an empty Swordfish LiveView runtime.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Adds a resource to the LiveView runtime.
  """
  @spec add_resource(t(), atom(), Swordfish.Resource.t()) :: t()
  def add_resource(%__MODULE__{resources: resources} = runtime, name, resource)
      when is_atom(name) do
    %{runtime | resources: Map.put(resources, name, resource)}
  end

  @doc """
  Adds an action to the LiveView runtime.
  """
  @spec add_action(t(), Swordfish.Action.t()) :: t()
  def add_action(%__MODULE__{actions: actions} = runtime, %Swordfish.Action{name: name} = action) do
    %{runtime | actions: Map.put(actions, name, action)}
  end

  @doc """
  Sets the approved context for the LiveView runtime.
  """
  @spec put_context(t(), Swordfish.Context.t()) :: t()
  def put_context(%__MODULE__{} = runtime, %Swordfish.Context{} = context) do
    %{runtime | context: context}
  end

  @doc """
  Returns a named resource from the runtime.
  """
  @spec resource(t(), atom()) :: Swordfish.Resource.t() | nil
  def resource(%__MODULE__{resources: resources}, name), do: Map.get(resources, name)

  @doc """
  Returns a named action from the runtime.
  """
  @spec action(t(), atom()) :: Swordfish.Action.t() | nil
  def action(%__MODULE__{actions: actions}, name), do: Map.get(actions, name)

  defp compile_action({name, opts}) do
    Keyword.get(opts, :discovery)
    |> case do
      nil ->
        Swordfish.Action.new(name, opts)

      discovery ->
        capability = build_capability(discovery)

        action_opts =
          opts
          |> Keyword.delete(:discovery)
          |> Keyword.put(:capability, capability)

        Swordfish.Action.new(name, action_opts)
    end
  end

  defp build_capability(discovery) when is_list(discovery) do
    discovery_module = Keyword.fetch!(discovery, :module)
    discovery_name = Keyword.fetch!(discovery, :name)
    assigns = Keyword.get(discovery, :assigns, [])

    Swordfish.Action.Capability.new(discovery_module, discovery_name, assigns)
  end
end
