# Changelog

All notable changes to `TerminalAgentSession` will be documented in this file.

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
