import Foundation
import Synchronization
import AgentAtom

/// Unified terminal agent session that automatically detects installed CLI tools or wraps any `TerminalSessionProtocol`.
/// Supports pluggable third-party providers and custom packages without hardcoding.
public final class TerminalAgentSession: TerminalSessionProtocol {
    public typealias Configuration = TerminalAgentConfiguration

    /// Built-in and registered providers.
    public static var standardProviders: [TerminalProvider] {
        [
            TerminalProvider(name: "codex", defaultExecutablePath: "codex") { CodexTerminalSession(configuration: $0) },
            TerminalProvider(name: "antigravity", defaultExecutablePath: "agy") { AntigravityTerminalSession(configuration: $0) },
            TerminalProvider(name: "grok", defaultExecutablePath: "grok") { GrokTerminalSession(configuration: $0) }
        ]
    }

    private let underlying: any TerminalSessionProtocol

    public var configuration: TerminalAgentConfiguration {
        underlying.configuration
    }

    public var executionMetadata: [AgenticExecutionMetadata] {
        underlying.executionMetadata
    }

    /// Creates a session by auto-detecting the first available provider from candidate providers.
    /// Allows custom/external providers to be passed or prepended easily.
    public convenience init?(
        providers: [TerminalProvider] = TerminalAgentSession.standardProviders,
        workingDirectory: URL? = nil,
        metadata: AgenticExecutionMetadata.Fields = []
    ) {
        for provider in providers {
            let config = TerminalAgentConfiguration(
                executablePath: provider.defaultExecutablePath,
                workingDirectory: workingDirectory,
                metadata: metadata
            )
            if let session = provider.createSession(configuration: config) {
                self.init(session: session)
                return
            }
        }
        return nil
    }

    /// Creates a session using a specific provider descriptor and optional configuration.
    public convenience init?(
        provider: TerminalProvider,
        configuration: TerminalAgentConfiguration? = nil
    ) {
        let config = configuration ?? TerminalAgentConfiguration(executablePath: provider.defaultExecutablePath)
        guard let session = provider.createSession(configuration: config) else { return nil }
        self.init(session: session)
    }

    /// Convenience to instantiate ANY command-line agent tool (e.g. `muse`, `claude`, `ollama`) directly.
    public convenience init?(
        executablePath: String,
        model: String? = nil,
        workingDirectory: URL? = nil,
        extraArguments: CLIArguments = []
    ) {
        guard let session = GenericTerminalSession(
            executablePath: executablePath,
            model: model,
            workingDirectory: workingDirectory,
            extraArguments: extraArguments
        ) else { return nil }
        self.init(session: session)
    }

    public convenience init?(
        executablePath: String,
        model: String? = nil,
        workingDirectory: URL? = nil,
        extraArguments: [String]
    ) {
        self.init(
            executablePath: executablePath,
            model: model,
            workingDirectory: workingDirectory,
            extraArguments: CLIArguments(extraArguments)
        )
    }

    /// Wraps any existing `TerminalSessionProtocol` implementation (from this package or any external package).
    public init(session: any TerminalSessionProtocol) {
        self.underlying = session
    }

    public func clearMemory() {
        underlying.clearMemory()
    }

    public func purgeMemory() {
        underlying.purgeMemory()
    }

    public func respond(
        to input: String,
        instructions: String,
        schema: JSONString,
        for operation: ObjectIdentifier
    ) async -> Result<String, AgenticError> {
        await underlying.respond(to: input, instructions: instructions, schema: schema, for: operation)
    }

    public func stream(
        to input: String,
        instructions: String,
        schema: JSONString,
        for operation: ObjectIdentifier,
        yield: @Sendable (String) async -> Void
    ) async -> Result<String, AgenticError> {
        await underlying.stream(to: input, instructions: instructions, schema: schema, for: operation, yield: yield)
    }

    public func pause(_ operation: ObjectIdentifier) async throws(AgenticError) {
        try await underlying.pause(operation)
    }

    public func resume(_ operation: ObjectIdentifier) async throws(AgenticError) {
        try await underlying.resume(operation)
    }
}
