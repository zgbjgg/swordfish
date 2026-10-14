defmodule Swordfish.Provider.OpenAITest do
  use ExUnit.Case

  alias Swordfish.Provider.OpenAI
  alias Swordfish.Tool

  setup do
    Application.put_env(
      :swordfish,
      OpenAI,
      api_key: "test-key"
    )

    on_exit(fn ->
      Application.delete_env(:swordfish, OpenAI)
    end)

    :ok
  end

  test "translates tools and normalizes function calls" do
    Tesla.Mock.mock(fn env ->
      send(self(), {:request, env})

      Tesla.Mock.json(%{
        "output" => [
          %{
            "type" => "function_call",
            "call_id" => "call-1",
            "name" => "query_tickets",
            "arguments" => Jason.encode!(%{"limit" => 20})
          }
        ]
      })
    end)

    tool = Tool.new("query_tickets", "Query tickets", %{"type" => "object"})

    assert {:ok,
            %{
              type: :tool_call,
              tool_call: %{id: "call-1", name: "query_tickets", arguments: %{"limit" => 20}}
            }} =
             OpenAI.chat(
               [%{"role" => "user", "content" => "show tickets"}],
               [tool],
               endpoint: "https://example.test/v1/responses"
             )

    assert_received {:request, request}
    assert request.method == :post
    assert request.url == "https://example.test/v1/responses"
    assert {"authorization", "Bearer test-key"} in request.headers
    assert {"content-type", "application/json"} in request.headers

    payload = Jason.decode!(request.body)
    assert payload["model"] == "gpt-5.6-luna"
    assert payload["input"] == [%{"role" => "user", "content" => "show tickets"}]
    [function] = payload["tools"]
    assert function["type"] == "function"
    assert function["name"] == "query_tickets"
    assert function["parameters"] == %{"type" => "object"}
  end

  test "normalizes a text response" do
    Tesla.Mock.mock(fn _env ->
      Tesla.Mock.json(%{
        "output" => [
          %{
            "type" => "message",
            "content" => [
              %{"type" => "output_text", "text" => "There are no open tickets."}
            ]
          }
        ]
      })
    end)

    assert {:ok, %{type: :message, content: "There are no open tickets."}} = OpenAI.chat([], [])
  end

  test "returns an error when the API key is missing" do
    Application.delete_env(:swordfish, OpenAI)

    assert {:error, :missing_openai_api_key} = OpenAI.chat([], [])
  end

  test "does not accept an API key from chat options" do
    Tesla.Mock.mock(fn env ->
      send(self(), {:request, env})

      Tesla.Mock.json(%{
        "output" => [
          %{
            "type" => "message",
            "content" => [%{"type" => "output_text", "text" => "ok"}]
          }
        ]
      })
    end)

    assert {:ok, %{type: :message, content: "ok"}} = OpenAI.chat([], [], api_key: "ignored")

    assert_received {:request, request}
    assert {"authorization", "Bearer test-key"} in request.headers
  end

  test "uses the configured HTTP adapter and adapter options" do
    Application.put_env(
      :swordfish,
      OpenAI,
      api_key: "test-key",
      http_adapter_options: [recv_timeout: 15_000]
    )

    Tesla.Mock.mock(fn _env ->
      Tesla.Mock.json(%{
        "output" => [
          %{
            "type" => "message",
            "content" => [%{"type" => "output_text", "text" => "ok"}]
          }
        ]
      })
    end)

    assert {:ok, %{type: :message, content: "ok"}} = OpenAI.chat([], [])
  end
end
