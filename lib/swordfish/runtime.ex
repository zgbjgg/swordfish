defmodule Swordfish.Runtime do
  @moduledoc """
  Provider-independent orchestration for Swordfish.

  The runtime turns a user message into either a final response, a validated
  query intent or an action intent. It never executes a Repo operation or
  mutates a Phoenix socket.
  """

  alias Swordfish.Action
  alias Swordfish.Action.Capability
  alias Swordfish.LiveView
  alias Swordfish.Intent
  alias Swordfish.LiveView.Toolbox
  alias Swordfish.Policy
  alias Swordfish.Query.Executor
  alias Swordfish.Runtime.Result
  alias Swordfish.Tool

  @type t :: %__MODULE__{
          live_view: LiveView.t(),
          provider: module(),
          policy: Policy.t()
        }

  defstruct [
    :live_view,
    :provider,
    :policy
  ]

  @doc """
  Creates a Swordfish runtime from a LiveView runtime, provider and policy.
  """
  @spec new(LiveView.t(), module(), Policy.t()) :: t()
  def new(%LiveView{} = live_view, provider, %Policy{} = policy) when is_atom(provider) do
    %__MODULE__{
      live_view: live_view,
      provider: provider,
      policy: policy
    }
  end

  @doc """
  Sends a user message through the configured provider and handles its first response.
  """
  @spec run(t(), String.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def run(%__MODULE__{} = runtime, message, opts \\ []) when is_binary(message) do
    runtime
    |> messages(message, opts)
    |> provider_call(runtime, opts)
    |> normalize_response()
    |> handle_response(runtime)
  end

  defp messages(runtime, message, opts) do
    system_message = Keyword.get(opts, :system_message, context_message(runtime.live_view))

    case system_message do
      nil ->
        [%{"role" => "user", "content" => message}]

      value ->
        [%{"role" => "system", "content" => value}, %{"role" => "user", "content" => message}]
    end
  end

  defp provider_call(messages, runtime, opts) do
    provider_tools(runtime.live_view)
    |> case do
      {:ok, tools} -> runtime.provider.chat(messages, tools, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp provider_tools(live_view) do
    toolbox = Toolbox.tools(live_view)

    query_tools = Enum.map(toolbox.queries, &query_tool/1)

    resolve_action_tools(toolbox.actions, live_view.context, [])
    |> case do
      {:ok, action_tools} -> {:ok, query_tools ++ action_tools}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_action_tools([], _context, resolved), do: {:ok, Enum.reverse(resolved)}

  defp resolve_action_tools([action | rest], context, resolved) do
    action_tool(action, context)
    |> case do
      {:ok, tool} -> resolve_action_tools(rest, context, [tool | resolved])
      {:error, reason} -> {:error, {:action_tool, action.name, reason}}
    end
  end

  defp query_tool(tool) do
    Tool.new(tool.name, tool.description, tool.input_schema)
  end

  defp action_tool(%Action{capability: nil} = action, _context) do
    {:ok,
     Tool.new(
       Atom.to_string(action.name),
       action.description,
       action.input_schema,
       action.handler
     )}
  end

  defp action_tool(%Action{capability: %Capability{} = capability} = action, context) do
    Capability.resolve(capability, context)
    |> case do
      {:ok, resolved_tool} ->
        {:ok,
         Tool.new(
           Atom.to_string(action.name),
           action.description,
           resolved_tool.input_schema,
           action.handler
         )}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_response({:ok, response}) do
    {:ok, response}
  end

  defp normalize_response({:error, reason}) do
    {:error, reason}
  end

  defp normalize_response(response) when is_map(response) do
    {:ok, response}
  end

  defp handle_response({:error, reason}, _runtime) do
    {:ok, Result.error({:provider, reason})}
  end

  defp handle_response({:ok, response}, runtime) do
    response
    |> response_type()
    |> handle_response_type(response, runtime)
  end

  defp handle_response_type(:message, response, _runtime) do
    {:ok, Result.responded(response_content(response))}
  end

  defp handle_response_type(:tool_call, response, runtime) do
    handle_tool_call(response, runtime)
  end

  defp handle_response_type(:unknown, _response, _runtime) do
    {:ok, Result.error(:invalid_provider_response)}
  end

  defp response_type(%{type: type}) when type in [:message, "message"], do: :message
  defp response_type(%{"type" => type}) when type in [:message, "message"], do: :message
  defp response_type(%{type: type}) when type in [:tool_call, "tool_call"], do: :tool_call
  defp response_type(%{"type" => type}) when type in [:tool_call, "tool_call"], do: :tool_call
  defp response_type(_response), do: :unknown

  defp response_content(%{content: content}) when is_binary(content), do: content
  defp response_content(%{"content" => content}) when is_binary(content), do: content
  defp response_content(_response), do: ""

  defp handle_tool_call(response, runtime) do
    call = tool_call(response)

    case call do
      %{name: name, arguments: arguments, id: id} -> dispatch_tool(name, arguments, id, runtime)
      _ -> {:ok, Result.error(:invalid_tool_call)}
    end
  end

  defp tool_call(%{tool_call: call}) when is_map(call), do: normalize_tool_call(call)
  defp tool_call(%{"tool_call" => call}) when is_map(call), do: normalize_tool_call(call)
  defp tool_call(_response), do: nil

  defp normalize_tool_call(call) do
    %{
      id: Map.get(call, :id, Map.get(call, "id")),
      name: Map.get(call, :name, Map.get(call, "name")),
      arguments: Map.get(call, :arguments, Map.get(call, "arguments", %{}))
    }
  end

  defp dispatch_tool(name, arguments, tool_call_id, runtime) do
    find_query_resource(runtime.live_view, name)
    |> case do
      {:ok, resource} -> compile_query(resource, arguments, tool_call_id, runtime.policy)
      :error -> dispatch_action(name, arguments, tool_call_id, runtime.live_view)
    end
  end

  defp find_query_resource(%LiveView{resources: resources}, name) do
    query_resource_name(name)
    |> case do
      {:ok, resource_name} -> find_resource_by_name(resources, resource_name)
      :error -> :error
    end
  end

  defp find_resource_by_name(resources, name) do
    Enum.find(resources, &(Atom.to_string(elem(&1, 0)) == name))
    |> case do
      nil -> :error
      {_key, resource} -> {:ok, resource}
    end
  end

  defp query_resource_name("query_" <> name), do: {:ok, name}
  defp query_resource_name(_name), do: :error

  defp compile_query(resource, arguments, tool_call_id, policy) do
    Executor.compile(resource, arguments, policy)
    |> case do
      {:ok, ecto_query} ->
        query = decode_query(resource, arguments)
        {:ok, Result.query(query, ecto_query, tool_call_id)}

      {:error, reason} ->
        {:ok, Result.error({:query, reason})}
    end
  end

  defp decode_query(resource, arguments) do
    Swordfish.Query.Decoder.from_map(resource, arguments)
    |> case do
      {:ok, query} -> query
      {:error, reason} -> raise "query was compiled but could not be decoded: #{inspect(reason)}"
    end
  end

  defp find_action(%LiveView{actions: actions}, name) do
    Enum.find(actions, &(Atom.to_string(elem(&1, 0)) == name))
    |> case do
      nil -> nil
      {_key, action} -> action
    end
  end

  defp dispatch_action(name, arguments, tool_call_id, live_view) do
    name
    |> action_name()
    |> find_action_for_dispatch(name, live_view, arguments, tool_call_id)
  end

  defp find_action_for_dispatch({:ok, action_name}, _name, live_view, arguments, tool_call_id) do
    find_action(live_view, action_name)
    |> case do
      %Action{} = action -> validate_action(action, arguments, tool_call_id, live_view.context)
      nil -> {:ok, Result.error({:unknown_tool, action_name})}
    end
  end

  defp find_action_for_dispatch(:error, name, _live_view, _arguments, _tool_call_id),
    do: {:ok, Result.error({:unknown_tool, name})}

  defp action_name(name) when is_binary(name), do: {:ok, name}
  defp action_name(_name), do: :error

  defp validate_action(
         %Action{} = action,
         arguments,
         tool_call_id,
         context
       )
       when is_map(arguments) do
    action
    |> action_tool(context)
    |> validate_resolved_action(action, arguments, tool_call_id)
  end

  defp validate_action(_action, _arguments, _tool_call_id, _context) do
    {:ok, Result.error(:invalid_action_arguments)}
  end

  defp validate_resolved_action({:ok, tool}, action, arguments, tool_call_id) do
    intent = Intent.new(tool_call_id, Atom.to_string(action.name), arguments)

    Intent.validate(intent, [tool])
    |> case do
      {:ok, validated_intent} ->
        resolved_action = %{action | input_schema: tool.input_schema}
        {:ok, Result.action(resolved_action, validated_intent.arguments, tool_call_id)}

      {:error, reason} ->
        {:ok, Result.error({:action, reason})}
    end
  end

  defp validate_resolved_action({:error, reason}, action, _arguments, _tool_call_id),
    do: {:ok, Result.error({:action_tool, action.name, reason})}

  defp context_message(%LiveView{context: %Swordfish.Context{values: values}})
       when map_size(values) == 0,
       do: nil

  defp context_message(%LiveView{context: %Swordfish.Context{values: values}}) do
    "Application-approved context: #{inspect(values)}"
  end
end
