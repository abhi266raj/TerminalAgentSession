# Changelog

All notable changes to `TerminalAgentSession` will be documented in this file.

## [0.1.3] - 2026-10-16

### Fixed
- Attach the Antigravity print prompt to `--print=` so options cannot be consumed as the prompt.
- Propagate native failed statuses and error results even when the CLI exits successfully and supplies structured output.
- Apply both fixes to the binary-dependency and source-dependency library products.

## [0.1.2] - 2026-10-16

### Fixed
- Fixed `AntigravityTerminalSession` process persistence mode: defaults to ephemeral mode so prompt arguments are correctly passed rather than dropped.
- Added noninteractive `--print` flag and permissions flags to Antigravity CLI invocation.
- Enhanced Antigravity stream parser to handle `step_update`, `text_delta`, `structured_output`, and native `result` payload envelopes.

## [0.1.1] - 2026-10-16

### Added
- Added dual library products: `TerminalAgentSession` (for `AgentAtom` dynamic binary) and `TerminalAgentSessionSource` (for `AgentAtomSource` pure source build).
- Added `TerminalAgentSessionSourceTests` test suite validating the pure source target.

## [0.1.0] - 2026-10-16

### Added
- Initial standalone release of `TerminalAgentSession`.
- Full conformance to `AgentAtom.AgenticSessionProtocol` (pinned to `AgentAtom 0.1.0`).
- Process-driven CLI providers:
  - `CodexTerminalSession`
  - `AntigravityTerminalSession`
  - `GrokTerminalSession`
  - `GenericTerminalSession`
- `TerminalAgentSession` multi-provider dispatcher with auto-discovery (`Codex` -> `Antigravity` -> `Grok`).
- Persistence modes: `.ephemeral`, `.daemon`, and `.persistentStdio`.
- Memory retention policies: `.keepAll` and `.clear`.
- Typed execution convenience extensions (`execute(spec)`, `executeFailable(spec)`, `respond(input:instructions:outputType:)`).
- Strict JSON schema sanitization for OpenAI Draft 2020-12 compliance.
- Complete unit test suite with mock CLI subprocesses.
- AGPL-3.0-only license and contributor guidance.
