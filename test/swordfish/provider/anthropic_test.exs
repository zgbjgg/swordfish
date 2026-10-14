defmodule Swordfish.Provider.AnthropicTest do
  use ExUnit.Case

  alias Swordfish.Provider.Anthropic
  alias Swordfish.Tool

  setup do
    Application.put_env(
      :swordfish,
      Anthropic,
      api_key: "test-key"
    )

    on_exit(fn ->
      Application.delete_env(:swordfish, Anthropic)
    end)

    :ok
  end

  test "translates tools and normalizes tool use" do
    Tesla.Mock.mock(fn env ->
      send(self(), {:request, env})

      Tesla.Mock.json(%{
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "toolu-1",
            "name" => "query_tickets",
            "input" => %{"limit" => 20}
          }
        ]
      })
    end)

    tool = Tool.new("query_tickets", "Query tickets", %{"type" => "object"})

    assert {:ok,
            %{
              type: :tool_call,
              tool_call: %{id: "toolu-1", name: "query_tickets", arguments: %{"limit" => 20}
            }}} =
             Anthropic.chat(
               [%{"role" => "user", "content" => "show tickets"}],
               [tool],
               endpoint: "https://example.test/v1/messages"
             )

    assert_received {:request, request}
    assert request.method == :post
    assert request.url == "https://example.test/v1/messages"
    assert {"x-api-key", "test-key"} in request.headers
    assert {"anthropic-version", "2023-06-01"} in request.headers
    assert {"content-type", "application/json"} in request.headers

    payload = Jason.decode!(request.body)
    assert payload["model"] == "claude-sonnet-5"
    assert payload["max_tokens"] == 1024
    assert payload["messages"] == [%{"role" => "user", "content" => "show tickets"}]
    [function] = payload["tools"]
    assert function["name"] == "query_tickets"
    assert function["description"] == "Query tickets"
    assert function["input_schema"] == %{"type" => "object"}
  end

  test "moves system messages to the Anthropic system field" do
    Tesla.Mock.mock(fn env ->
      send(self(), {:request, env})
      Tesla.Mock.json(%{"content" => [%{"type" => "text", "text" => "ok"}]})
    end)

    assert {:ok, %{type: :message, content: "ok"}} =
             Anthropic.chat([
               %{"role" => "system", "content" => "Be concise."},
               %{"role" => "user", "content" => "hello"}
             ], [])

    assert_received {:request, request}
    payload = Jason.decode!(request.body)
    assert payload["system"] == "Be concise."
    assert payload["messages"] == [%{"role" => "user", "content" => "hello"}]
  end

  test "normalizes a text response" do
    Tesla.Mock.mock(fn _env ->
      Tesla.Mock.json(%{
        "content" => [
          %{"type" => "text", "text" => "There are no open tickets."}
        ]
      })
    end)

    assert {:ok, %{type: :message, content: "There are no open tickets."}} =
             Anthropic.chat([], [])
  end

  test "returns an error when the API key is missing" do
    Application.delete_env(:swordfish, Anthropic)

    assert {:error, :missing_anthropic_api_key} = Anthropic.chat([], [])
  end

  test "does not accept an API key from chat options" do
    Tesla.Mock.mock(fn env ->
      send(self(), {:request, env})
      Tesla.Mock.json(%{"content" => [%{"type" => "text", "text" => "ok"}]})
    end)

    assert {:ok, %{type: :message, content: "ok"}} =
             Anthropic.chat([], [], api_key: "ignored")

    assert_received {:request, request}
    assert {"x-api-key", "test-key"} in request.headers
  end
end
