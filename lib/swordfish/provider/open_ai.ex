defmodule Swordfish.Provider.OpenAI do
  @moduledoc """
  OpenAI provider adapter for Swordfish.

  The adapter translates provider-neutral Swordfish tools into the OpenAI
  Responses API format and normalizes function calls into the response shape
  expected by Swordfish.Runtime.
  """

  @behaviour Swordfish.Provider

  @default_endpoint "https://api.openai.com/v1/responses"
  @default_model "gpt-5.6-luna"

  @doc """
  Sends messages and provider-neutral tools to the OpenAI Responses API.
  """
  @spec chat(list(), list(Swordfish.Tool.t()), keyword()) ::
          {:ok, map()} | {:error, term()}
  def chat(messages, tools, opts \\ []) do
    config = Application.get_env(:swordfish, __MODULE__, [])
    api_key = Keyword.get(config, :api_key)
    endpoint = Keyword.get(opts, :endpoint, Keyword.get(config, :endpoint, @default_endpoint))
    model = Keyword.get(opts, :model, Keyword.get(config, :model, @default_model))
    http_client = Keyword.get(opts, :http_client, Swordfish.Provider.OpenAI.HTTPClient)
    http_adapter_options = Keyword.get(config, :http_adapter_options, [])
    request_opts = Keyword.put(opts, :http_adapter_options, http_adapter_options)

    case api_key do
      key when is_binary(key) and key != "" ->
        request(messages, tools, key, endpoint, model, http_client, request_opts)

      _ ->
        {:error, :missing_openai_api_key}
    end
  end

  defp request(messages, tools, api_key, endpoint, model, http_client, opts) do
    body = %{
      "model" => model,
      "input" => messages,
      "tools" => Enum.map(tools, &Swordfish.Provider.OpenAI.Tool.from/1)
    }

    http_client.request(endpoint, headers(api_key), body, opts)
    |> handle_request_response()
  end

  defp handle_request_response({:ok, status, response_body})
       when status >= 200 and status < 300 do
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
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]
  end

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

  defp normalize_response(%{"output" => output}) when is_list(output) do
    normalize_output(output)
  end

  defp normalize_response(%{"error" => error}) do
    {:error, {:provider, error}}
  end

  defp normalize_response(_response) do
    {:error, :invalid_openai_response}
  end

  defp normalize_output(output) do
    Enum.find(output, &function_call?/1)
    |> case do
      nil -> normalize_message_output(output)
      function_call -> normalize_function_call(function_call)
    end
  end

  defp function_call?(%{"type" => "function_call"}), do: true
  defp function_call?(_output), do: false

  defp normalize_function_call(%{
         "type" => "function_call",
         "call_id" => id,
         "name" => name,
         "arguments" => arguments
       }) do
    Jason.decode(arguments)
    |> case do
      {:ok, decoded_arguments} when is_map(decoded_arguments) ->
        {:ok,
         %{
           type: :tool_call,
           tool_call: %{id: id, name: name, arguments: decoded_arguments}
         }}

      {:error, reason} ->
        {:error, {:invalid_tool_arguments, reason}}
    end
  end

  defp normalize_function_call(_output) do
    {:error, :invalid_openai_tool_call}
  end

  defp normalize_message_output(output) do
    Enum.reduce_while(output, :error, &output_text/2)
    |> case do
      {:ok, content} -> {:ok, %{type: :message, content: content}}
      :error -> {:error, :invalid_openai_message}
    end
  end

  defp output_text(%{"type" => "message", "content" => content}, _acc) do
    message_text(content)
    |> case do
      {:ok, text} -> {:halt, {:ok, text}}
      :error -> {:cont, :error}
    end
  end

  defp output_text(_item, acc), do: {:cont, acc}

  defp message_text(content) when is_list(content) do
    Enum.find_value(content, &content_text/1)
    |> case do
      nil -> :error
      text -> {:ok, text}
    end
  end

  defp message_text(_content), do: :error

  defp content_text(%{"type" => "output_text", "text" => text}) when is_binary(text), do: text
  defp content_text(_content), do: nil
end
