defmodule Swordfish.Provider.Anthropic do
  @moduledoc """
  Anthropic provider adapter for Swordfish.

  The adapter translates provider-neutral Swordfish tools into the Anthropic
  Messages API format and normalizes tool calls into the response shape
  expected by Swordfish.Runtime.
  """

  @behaviour Swordfish.Provider

  @default_endpoint "https://api.anthropic.com/v1/messages"
  @default_model "claude-sonnet-5"
  @default_max_tokens 1024
  @anthropic_version "2023-06-01"

  @doc "Sends messages and provider-neutral tools to the Anthropic Messages API."
  @spec chat(list(), list(Swordfish.Tool.t()), keyword()) ::
          {:ok, map()} | {:error, term()}
  def chat(messages, tools, opts \\ []) do
    config = Application.get_env(:swordfish, __MODULE__, [])
    api_key = Keyword.get(config, :api_key)
    endpoint = Keyword.get(opts, :endpoint, Keyword.get(config, :endpoint, @default_endpoint))
    model = Keyword.get(opts, :model, Keyword.get(config, :model, @default_model))
    max_tokens = Keyword.get(opts, :max_tokens, Keyword.get(config, :max_tokens, @default_max_tokens))
    http_client = Keyword.get(opts, :http_client, Swordfish.Provider.Anthropic.HTTPClient)
    http_adapter_options = Keyword.get(config, :http_adapter_options, [])
    request_opts = Keyword.put(opts, :http_adapter_options, http_adapter_options)

    case api_key do
      key when is_binary(key) and key != "" ->
        request(messages, tools, key, endpoint, model, max_tokens, http_client, request_opts)

      _ ->
        {:error, :missing_anthropic_api_key}
    end
  end

  defp request(messages, tools, api_key, endpoint, model, max_tokens, http_client, opts) do
    {system, conversation} = split_system_messages(messages)

    body = %{
      "model" => model,
      "max_tokens" => max_tokens,
      "messages" => conversation,
      "tools" => Enum.map(tools, &Swordfish.Provider.Anthropic.Tool.from/1)
    }

    body = add_system(body, system)

    http_client.request(endpoint, headers(api_key), body, opts)
    |> handle_request_response()
  end

  defp handle_request_response({:ok, status, response_body}) when status >= 200 and status < 300 do
    decode_response(response_body)
  end

  defp handle_request_response({:ok, status, response_body}) do
    {:error, {:http, status, response_body}}
  end

  defp handle_request_response({:error, reason}) do
    {:error, {:http, reason}}
  end

  defp headers(api_key) do
    [
      {"x-api-key", api_key},
      {"anthropic-version", @anthropic_version},
      {"content-type", "application/json"}
    ]
  end


  defp split_system_messages(messages) do
    {system_messages, conversation} = Enum.split_with(messages, &system_message?/1)
    {system_content(system_messages), conversation}
  end

  defp system_message?(%{"role" => "system"}), do: true
  defp system_message?(_message), do: false

  defp system_content([]), do: nil
  defp system_content(messages), do: Enum.map(messages, &system_message_content/1) |> Enum.join("\n")

  defp system_message_content(%{"role" => "system", "content" => content}), do: content

  defp add_system(body, nil), do: body
  defp add_system(body, system), do: Map.put(body, "system", system)

  defp decode_response(response_body) when is_map(response_body) do
    normalize_response(response_body)
  end

  defp decode_response(response_body) when is_binary(response_body) do
    Jason.decode(response_body)
    |> case do
      {:ok, response} -> normalize_response(response)
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp normalize_response(%{"content" => content}) when is_list(content) do
    normalize_content(content)
  end

  defp normalize_response(%{"type" => "error", "error" => error}) do
    {:error, {:provider, error}}
  end

  defp normalize_response(_response) do
    {:error, :invalid_anthropic_response}
  end

  defp normalize_content(content) do
    Enum.find(content, &tool_use?/1)
    |> case do
      nil -> normalize_text_content(content)
      tool_use -> normalize_tool_use(tool_use)
    end
  end

  defp tool_use?(%{"type" => "tool_use"}), do: true
  defp tool_use?(_content), do: false

  defp normalize_tool_use(%{
         "type" => "tool_use",
         "id" => id,
         "name" => name,
         "input" => input
       }) when is_map(input) do
    {:ok,
     %{
       type: :tool_call,
       tool_call: %{id: id, name: name, arguments: input}
     }}
  end

  defp normalize_tool_use(_content) do
    {:error, :invalid_anthropic_tool_call}
  end

  defp normalize_text_content(content) do
    Enum.find_value(content, &content_text/1)
    |> case do
      nil -> {:error, :invalid_anthropic_message}
      text -> {:ok, %{type: :message, content: text}}
    end
  end

  defp content_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp content_text(_content), do: nil
end
