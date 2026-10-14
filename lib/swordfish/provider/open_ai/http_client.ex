defmodule Swordfish.Provider.OpenAI.HTTPClient do
  @moduledoc "HTTP client used by Swordfish.Provider.OpenAI."

  use Tesla

  plug Tesla.Middleware.JSON

  @doc "Executes an HTTP POST request using Tesla and the configured HTTP adapter."
  @spec request(String.t(), list(), map(), keyword()) ::
          {:ok, non_neg_integer(), binary() | map()} | {:error, term()}
  def request(endpoint, headers, body, opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    adapter_options = Keyword.get(opts, :http_adapter_options, [])
    adapter_options = Keyword.merge([recv_timeout: timeout], adapter_options)

    request_opts = [
      headers: headers,
      opts: [adapter: adapter_options]
    ]

    post(endpoint, body, request_opts)
    |> case do
      {:ok, %Tesla.Env{status: status, body: response_body}} ->
        {:ok, status, response_body}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
