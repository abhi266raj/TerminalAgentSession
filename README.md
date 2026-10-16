# TerminalAgentSession

A lightweight, zero-server-dependency Swift package implementing `AgentAtom.AgenticSessionProtocol` for terminal-installed AI coding agents and CLI providers:
- **Codex CLI** (`codex exec`)
- **Antigravity CLI** (`agy`)
- **Grok CLI** (`grok`)

## Architecture & Integration

`TerminalAgentSession` conforms to `AgentAtom`'s `AgenticSessionProtocol`. It allows any `AgentAtom.Spec` or `ModelledSpec` (such as `NewsAgent.ShekharJokeGeneratorSpec`) to be executed via standard `AgenticOperation`, `FailableAgenticOperation`, or streaming operations with zero modifications to your spec.

### Dependencies
- [`AgentAtom`](https://github.com/abhi266raj/AgentAtom) (remote binary product, exact `0.1.0`)
- System Foundation process APIs

No server dependencies, HTTP libraries, or third-party networking packages are required.

## Features
- **Swift 6 Concurrency & Strict Sendability**: Actor isolation, non-blocking asynchronous streaming of lines, and thread-safe lock management.
- **Convenience Coding & Decoding Extensions**:
  - `session.execute(spec)`: Runs a `ModelledSpec` and directly returns decoded `Spec.Output`.
  - `session.executeFailable(spec)`: Runs a failable `ModelledSpec` and decodes the result.
  - `session.respond(input:instructions:outputType:)`: Directly encodes an Encodable input, derives the JSON schema, runs the terminal agent, and decodes the typed response.
- **Strict Schema Bridging**: Built-in Draft 2020-12 sanitizer for OpenAI / Codex strict structured output requirements.
- **Provider Detection & Custom Configuration**: Automatic provider selection (`Codex` -> `Antigravity` -> `Grok`) or explicit provider instantiation with custom models, arguments, and working directories.

## Usage Example

```swift
import TerminalAgentSession
import NewsAgent

// 1. Initialize session (auto-detected or explicit)
guard let session = TerminalAgentSession() else {
    fatalError("No terminal agent CLI installed")
}

// 2. Instantiate any ModelledSpec
let spec = ShekharJokeGeneratorSpec(
    categories: ["Politics", "Tech"],
    newsArticles: [
        .init(title: "AI Breakthrough", content: "New model sets benchmarks", source: "TechNews")
    ],
    outputCount: 4,
    newsCount: 1,
    jokesPerCategory: 2
)

// 3. Execute with automatic encoding & decoding convenience
let result = try await session.execute(spec)
for item in result.items {
    print("[\(item.category)] \(item.joke)")
}
```

## Distribution & Dual Products

`TerminalAgentSession` provides two SwiftPM library products from the exact same package URL:

- **`TerminalAgentSession`** (`import TerminalAgentSession`):
  Uses the standard binary `AgentAtom` framework. Recommended default for applications and servers consuming the binary `AgentAtom` XCFramework.
- **`TerminalAgentSessionSource`** (`import TerminalAgentSessionSource`):
  Pure source product that pairs directly with `AgentAtomSource` (`import AgentAtomSource`). Ideal for clean source-only builds and environments avoiding dynamic frameworks.

> **Note**: Choose one product per dependency graph to keep type module identities consistent. Both products provide the exact same APIs and are licensed under **AGPL-3.0-only**.
