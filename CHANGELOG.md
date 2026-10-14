# Changelog

All notable changes to Swordfish are documented here.

## [1.3.0] - 2026-10-03

- Removed application-specific domain terminology from documentation, examples, and tests.
- Standardized generic examples and test fixtures.
- Added strict coding conventions and AI-assisted development guidance.
- Preserved the existing application capability, discovery, provider, and validation behavior.

## [1.2.0]

- Added Discovery support for Phoenix `date_input` and `datetime_input` helpers.
- Added discovery support for native HTML date and datetime-local inputs.
- Added JSON Schema date and date-time formats.

## [1.1.0]

- Added entity resolution and metadata projection.
- Normalized `nil` to `[]` for multi-value enum/entity fields during intent validation.
- Preserved discovered resolvers when explicit field metadata is supplied.

## [1.0.0]

- Established the Application Capability workflow for exposing existing application actions and context to an LLM through structured, validated intents.
