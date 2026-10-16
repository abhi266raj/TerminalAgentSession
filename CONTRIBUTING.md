# Contributing to TerminalAgentSession

Thank you for contributing to TerminalAgentSession!

## Guiding Principles & Laws of AgentAtom

1. **Purity**:
   - `TerminalAgentSession` depends solely on `AgentAtom` (exact version pin) and system Foundation libraries.
   - It must never depend on any concrete domain agent package (e.g. `NewsAgent`, `ShekharJokeGenerator`), HTTP servers, or monorepo tools.
2. **Strict Concurrency**:
   - Written in Swift 6 mode with complete Sendable checking.
   - All session state transitions are thread-safe and isolated.
3. **Deterministic Mock Testing**:
   - Unit tests use simulated CLI subprocesses and mock scripts rather than expecting external AI tools installed in the environment.
4. **License**:
   - Licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0-only)**. Contributions are under the same license terms.

## Development Workflow

1. Fork or clone the repository:
   ```sh
   git clone https://github.com/abhi266raj/TerminalAgentSession.git
   ```
2. Build the package:
   ```sh
   swift build
   ```
3. Run the automated tests:
   ```sh
   swift test
   ```
4. Ensure your changes compile cleanly under Swift 6.
