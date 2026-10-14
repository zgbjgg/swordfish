# Swordfish

Open-source declarative AI integration for Elixir/Phoenix. Swordfish lets an LLM propose structured queries or application actions while Elixir remains responsible for discovery, validation, and execution.

> **Core rule:** the LLM proposes; Swordfish validates; the application executes.

[![Hex.pm](https://img.shields.io/hexpm/v/swordfish.svg)](https://hex.pm/packages/swordfish) 
[![Build Status](https://github.com/zgbjgg/swordfish/actions/workflows/ci.yml/badge.svg)](https://github.com/zgbjgg/swordfish/actions/workflows/ci.yml)
[![Codecov](https://img.shields.io/codecov/c/github/zgbjgg/swordfish.svg)](https://codecov.io/gh/zgbjgg/swordfish)
[![License: MIT](https://img.shields.io/github/license/zgbjgg/swordfish.svg)](https://raw.githubusercontent.com/zgbjgg/swordfish/master/LICENSE)
[![Hex.pm](https://img.shields.io/hexpm/dt/swordfish.svg)](https://hex.pm/packages/swordfish)
[![Hex.pm](https://img.shields.io/hexpm/dw/swordfish.svg)](https://hex.pm/packages/swordfish)
[![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/swordfish)

## What changed in v1.3.1

- Fixed OpenAI tool schema validation: Updated Swordfish.Query.Schema to prevent HTTP 400 errors when submitting resource query tools.
- Improved filter value schemas: Added explicit support for scalar values and arrays, including in and not_in operators.
- Simplified path schemas: Removed array-valued enums from path; allowed fields and associations remain validated by Swordfish.Query.Decoder.
- Removed custom schema metadata: Removed x-resource from generated tool parameters.
- Improved schema compatibility: Explicitly declared required properties and disabled additional properties in the root query schema.

## What changed in v1.3.0

- Removed application-specific domain terminology from tests, examples, and documentation.
- Replaced domain-specific field names with generic application examples.
- Kept the production implementation unchanged; this release is a documentation and test fixture cleanup.

## v1.2.0 baseline

- Discovery recognizes Phoenix `date_input` and `datetime_input` helpers.
- HEEx `<input type="date">` and `<input type="datetime-local">` are discovered as typed date/datetime fields.
- `date_input` produces JSON Schema `format: "date"`; `datetime_input` produces `format: "date-time"`.
- Date and datetime fields work through the same Discovery → Contract → Schema → Tool → Intent validation flow.

## v1.1.0 baseline

- Application capabilities can discover `enum` and `entity` values from approved application code.
- Multi-value `enum` and `entity` fields expose `default: []` to providers.
- Entity options carry their real IDs plus human-readable labels so a provider can resolve requests such as `"with Acme Provider"` to the correct ID.
- During intent validation, `nil` for multi-value enum/entity fields is normalized to `[]`; ordinary nullable fields remain `nil`.
- `assigns` enriches discovered fields but never replaces an application resolver.
- Provider schemas hide Swordfish-internal discovery metadata while preserving the information needed by the model to choose valid entity IDs.

## Installation

Add `swordfish` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:swordfish, "~> 1.3.0"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## End-to-end flow

```text
Phoenix LiveView
      |
      | swordfish_action / swordfish_context / swordfish_resource
      v
Swordfish Discovery
      |
      v
Contract -> Schema -> Tool
      |
      | resolve approved enum/entity sources
      v
Provider Schema
      |
      | OpenAI / Anthropic tool definition
      v
LLM
      |
      | structured tool call / query intent
      v
Intent validation
      |
      +---- :action ------> application handles action
      +---- :query -------> application executes Ecto.Query
      +---- :responded ----> application displays message
      +---- :error --------> application handles error
```

Swordfish does not execute arbitrary Elixir, SQL, Repo calls, or LiveView socket mutations on behalf of the model.

## v8: Phoenix LiveView declarations

Swordfish now has a compile-time DSL for LiveViews.

```elixir
defmodule MyAppWeb.TicketLive do
  use MyAppWeb, :live_view
  use Swordfish.LiveView

  swordfish_resource :tickets, MyApp.Ticket,
    fields: [:status, :priority],
    associations: [
      customer: [
        schema: MyApp.Customer,
        fields: [:name]
      ]
    ]

  swordfish_action :clear_filters,
    description: "Clears all filters"

  swordfish_action :select_ticket,
    description: "Selects a ticket"

  swordfish_context :active_tab
  swordfish_context :current_filters
  swordfish_context :selected_ticket
end
```

The declarations are compiled into ordinary functions:

```elixir
MyAppWeb.TicketLive.swordfish_resources()
MyAppWeb.TicketLive.swordfish_actions()
MyAppWeb.TicketLive.swordfish_context_fields()
```

### Why compile-time declarations?

The LiveView explicitly declares what Swordfish can expose.

Swordfish does not inspect the socket or scrape arbitrary assigns.

```text
Phoenix LiveView
      |
      | explicit declarations
      v
Swordfish
      |
      +-- resources
      +-- actions
      +-- context
```


## OpenAI provider

Swordfish includes an OpenAI provider adapter that implements `Swordfish.Provider`.
It uses the OpenAI Responses API and normalizes function tool calls into the
provider-neutral response format expected by `Swordfish.Runtime`.

The OpenAI API key is required in the host application's Swordfish configuration.
Swordfish does not read API keys from environment variables and the provider does
not accept `api_key:` as a runtime option.

```elixir
# config/config.exs
config :swordfish, Swordfish.Provider.OpenAI,
  api_key: "your-openai-api-key",
  model: "gpt-5.6-luna",
  http_adapter_options: [recv_timeout: 30_000]
```

Then the provider can be used without passing credentials through the runtime:

```elixir
runtime = Swordfish.Runtime.new(live_view, Swordfish.Provider.OpenAI, policy)
Swordfish.Runtime.run(runtime, "Show me the open tickets")
```

The HTTP client is injectable for tests through `http_client:`. Production requests
use Tesla with the Hackney adapter; Tesla's default `:httpc` adapter is not used.

After changing dependencies, run `mix deps.get` before running the test suite.

## Anthropic provider

Swordfish also includes an Anthropic provider adapter that implements `Swordfish.Provider`.
It uses the Anthropic Messages API, translates Swordfish tools into Anthropic input schemas,
and normalizes `tool_use` blocks into the provider-neutral response format expected by
`Swordfish.Runtime`. Anthropic system messages are sent through the API's dedicated
`system` field.

The Anthropic API key is required in the host application's Swordfish configuration.
Swordfish does not read API keys from environment variables and the provider does not
accept `api_key:` as a runtime option.

```elixir
# config/config.exs
config :swordfish, Swordfish.Provider.Anthropic,
  api_key: "your-anthropic-api-key",
  model: "claude-sonnet-5",
  max_tokens: 1024,
  http_adapter_options: [recv_timeout: 30_000]
```

The Anthropic provider uses Tesla with Hackney in production and `Tesla.Mock` can be
selected as the HTTP adapter in tests without replacing Swordfish's HTTP client.


## Application integration boundary

Swordfish provides the discovery, schema, provider, intent-validation, and runtime layers. The host application remains responsible for connecting the validated result to its own lifecycle. Typical responsibilities include:

- building the approved runtime context;
- executing validated actions;
- executing returned Ecto queries through the application repository;
- displaying provider responses;
- preserving conversation or UI state when required.

## Contributing

Bug reports, focused improvements, and documentation updates are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## Compatibility

Swordfish v1.3.0 targets Elixir 1.11.3 and Ecto 3.6.x. The Ecto compiler uses the internal runtime join builder to support dynamically selected, allowlisted named bindings without relying on newer `as:` interpolation behavior.

Swordfish targets **Elixir 1.11.3** as its baseline.

The project avoids language features introduced after Elixir 1.11.3 and pins
its Mix requirement to the Elixir 1.11 release line with `~> 1.11.0`.

The Ecto integration targets the supported Ecto 3.x range declared in
`mix.exs`. Applications should verify the exact Ecto version used by their
Phoenix stack.

## Runtime

`Swordfish.Runtime` is the orchestration layer between Phoenix LiveView and an
LLM provider.

```text
user message
    ↓
Swordfish.Runtime
    ↓
Provider
    ↓
tool call
 ┌───────────────┐
 │ query / action│
 └───────────────┘
    ↓
Validator + Policy
    ↓
Runtime.Result
```

The runtime does **not** execute `Repo` calls and does **not** mutate a Phoenix
socket. A query returns a compiled `Ecto.Query`; an action returns an action
intent plus validated arguments. The LiveView/application decides what to do
next.

Example:

```elixir
runtime = Swordfish.Runtime.new(live_view_runtime, MyApp.AIProvider, policy)

{:ok, result} = Swordfish.Runtime.run(runtime, "show me the open tickets")

case result.status do
  :query -> Repo.all(result.ecto_query)
  :action -> handle_swordfish_action(result.action.name, result.arguments, socket)
  :responded -> result.message
  :error -> {:error, result.error}
end
```

## Ecto compatibility

Swordfish currently targets Elixir 1.11.3 and Ecto 3.6.x. The Ecto compiler uses Ecto query builders where runtime binding names are required, rather than interpolating runtime values into macro binding declarations.

Root and association fields are represented as Ecto dynamic expressions. Association bindings are resolved through allowlisted named bindings, so query construction does not rely on lexical variables that do not exist at compile time.

## Test support fixtures

Shared Ecto schemas used by the test suite live under `test/support/schemas/`.
They are compiled only in the test environment and are imported by tests instead
of defining schema modules inside individual test modules.


## OpenAI configuration

The provider requires configuration in the host application:

```elixir
config :swordfish, Swordfish.Provider.OpenAI,
  api_key: "your-openai-api-key",
  model: "gpt-5.6-luna",
  http_adapter_options: [recv_timeout: 30_000]
```

The API key is read only from the application configuration. `System.get_env/1`,
`OPENAI_API_KEY`, and runtime `api_key:` options are intentionally unsupported.

## Release history

- **v1.3.0** — generic open-source documentation/test terminology cleanup; production implementation unchanged.
- **v1.2.0** — Phoenix `date_input`, `datetime_input`, and native date/datetime input discovery.
- **v1.1.0** — entity/enum collection defaults, provider-visible entity IDs/labels, and `nil` → `[]` normalization.
- Earlier development history is preserved in the project Git history.

## Application discovery

Swordfish can represent application input fields without coupling the discovery model to a provider or frontend framework.

A dynamically resolved field uses an MFA source:

```elixir
%Swordfish.Field{
  name: :providers,
  type: :fn,
  multiple?: true,
  source: [ExampleProvider, :simple_list, []]
}
```

Static fields can keep their values directly in `source`.

The discovery AST layer currently supports remote function calls, local function calls as the current module MFA, and compile-time literal lists/maps. Runtime execution of discovered sources is handled by `Swordfish.Resolver`.

--- v52 changes ---
- Added Swordfish.Intent for provider-neutral tool calls.
- Added intent validation against allowed Swordfish tools and their input schemas.

### Explicit Discovery assign sources

Discovery reads public inputs from the sibling template. Application-specific dynamic assign sources are opt-in:

```elixir
Swordfish.Discovery.discover_contract(
  MyAppWeb.FilterForm,
  :search,
  assigns: [:customers, :warehouses]
)
```

Swordfish does not inspect application-specific LiveComponents such as a custom multi-select component. If a dynamic assign is part of the capability contract, declare it explicitly with `assigns:`.


## Date and datetime inputs

Swordfish Discovery recognizes Phoenix form helpers for temporal inputs:

```elixir
<%= date_input f, :start_date %>
<%= datetime_input f, :start_at %>
```

These are discovered as `:date` and `:datetime` fields respectively. The provider-neutral schema represents them as JSON Schema strings with `format: :date` and `format: :date_time`; provider adapters encode the latter as the standard JSON Schema `"date-time"` format.

## Stable verification

The v1.3.0 release was validated by the project test suite with **138 tests and 0 failures**. The suite covers Discovery, schemas, provider adapters, Intent validation, runtime behavior, and Query/Ecto functionality.

## Open-source repository

- License: MIT (see `LICENSE`).
- Contribution guidelines: `CONTRIBUTING.md`.
- Change history: `CHANGELOG.md`.
- Pull requests and bug reports should include reproducible generic examples and actual validation output. Never include credentials or private application data.
