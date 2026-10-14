# Swordfish

**Swordfish v1.3.0 — stable release**

> **Stable baseline:** v1.3.0 has been validated by the project test suite with 138 tests and 0 failures.

Open-source declarative AI integration for Elixir/Phoenix. Swordfish lets an LLM propose structured queries or application actions while Elixir remains responsible for discovery, validation, and execution.

> **Core rule:** the LLM proposes; Swordfish validates; the application executes.

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

## AI-assisted development / vibecoding

Swordfish is designed to be worked on with AI coding agents. The repository includes a canonical agent guide and architecture references:

- `AGENTS.md` — rules all coding agents must follow.
- `CLAUDE.md` — Claude-specific entry point.
- `ARCHITECTURE.md` — architectural boundaries and invariants.
- `VIBECODING.md` — recommended AI-assisted development workflow.

Agents should read `AGENTS.md` and `ARCHITECTURE.md` before changing code. The stable baseline is intentionally conservative: agents should prefer small, test-backed changes over broad refactors.

## Development conventions

The v1.3.0 stable baseline follows these strict coding conventions. They apply to
production code, tests, and future contributions:

1. **Never use `with`.** Use `case` and pattern matching instead.
2. **Avoid anonymous functions in `Enum` calls.** Prefer named functions or captures such as `&function/1`.
3. **Every public function must have `@doc` and `@spec`.**
4. **Keep `case` branches small.** If a `case` has more than three branches, prefer pattern matching or split the responsibility into focused functions.
5. **Think in pipelines.** Functions should read as input → transformations → decision → output.
6. **Prefer pipeline-based decisions.** When a `case` follows a transformation, express the transformation as a pipeline into the `case` where practical.
7. **Never nest `case`.** Use pipelines, helper functions, and pattern matching instead.
8. **Do not create one-call wrapper functions.** If a function only delegates to another function without adding semantic value, remove the wrapper or use a default argument when appropriate.
9. **Keep same-name/same-arity clauses grouped together.** All clauses of a function must be contiguous to avoid compiler warnings and preserve readable pattern matching.
10. **Public application resolvers only.** Swordfish must not introspect or bypass `defp`; application capabilities exposed to Swordfish must be public.
11. **Keep application logic in the application.** Swordfish discovers and validates capabilities; it must not recreate business rules or generate resolver logic from application conditionals.
12. **Keep Application Mode and Query Mode conceptually separate.** Shared infrastructure is allowed, but their semantic pipelines must not be collapsed into one abstraction.
13. **Keep Swordfish messages and documentation in English.** This includes errors, descriptions, and user-visible library messages.
14. **Keep tests and examples generic.** Do not use private domain names or fixtures from a consuming application; use generic names such as `Northwind`, providers, accounts, records, and search filters.

These conventions are part of the stable v1.3.0 development baseline and should be
maintained in subsequent releases.

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
- Contribution and coding rules: `CONTRIBUTING.md` and `AGENTS.md`.
- Change history: `CHANGELOG.md`.
- GitHub first-push and repository settings checklist: `GITHUB_RELEASE.md`.
- Pull requests and bug reports should include reproducible generic examples and actual validation output. Never include credentials or private application data.
