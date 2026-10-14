# Contributing to Swordfish

Swordfish v1.3.0 is the stable release baseline.

Bug reports, focused fixes, tests, and documentation improvements are welcome. Please keep changes scoped, preserve existing public behavior unless a change explicitly requires otherwise, and avoid including credentials or private application data.

## Development setup

Use the project's supported Elixir 1.11 release line and fetch dependencies:

```bash
mix deps.get
```

## Before submitting a change

Run the test suite and review compiler output:

```bash
MIX_ENV=test mix compile --warnings-as-errors
mix test
```

Include the actual commands and results in your pull request. Do not report checks that were not run. Add or update tests for behavior changes and prefer generic examples that other Elixir applications can understand.
