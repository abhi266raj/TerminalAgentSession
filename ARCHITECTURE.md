# Architecture of TerminalAgentSession

`TerminalAgentSession` bridges `AgentAtom`'s generic execution model (`AgenticSessionProtocol`) to command-line interface (CLI) driven AI coding engines.

## Key Components

1. **`TerminalSessionProtocol`**:
   - Refines `AgentAtom.AgenticSessionProtocol`.
   - Adds process management lifecycle hooks (`isBusy`, `clearMemory()`, `purgeMemory()`, `terminateProcess()`, `activeConversationID`, `setConversationID(_:)`).

2. **Engines and Process Management**:
   - `TerminalSessionEngine`: Manages the lifecycle of CLI processes, handling thread-safe lock synchronization (`Synchronization.Mutex`), streaming line accumulation, and memory retention policies (`.keepAll`, `.clear`).
   - `TerminalProcessRunner`: Spawns and manages asynchronous streaming of process stdout/stderr via `AsyncStream` and `FileHandle`.

3. **Concrete CLI Implementations**:
   - `AntigravityTerminalSession`: Executes tasks using `agy` (supporting prompt arguments, JSON schema generation, streaming text, and `--print` output extraction).
   - `CodexTerminalSession`: Executes tasks using `codex exec` (supporting draft-2020-12 schema sanitization, `--json` structured responses, and conversation resumption).
   - `GrokTerminalSession`: Executes tasks using `grok` CLI.
   - `GenericTerminalSession`: Generic CLI execution engine for any arbitrary local CLI tool.

4. **Convenience Coding Extensions**:
   - High-level typed helpers:
     - `session.execute(spec)`
     - `session.executeFailable(spec)`
     - `session.respond(input:instructions:outputType:)`
