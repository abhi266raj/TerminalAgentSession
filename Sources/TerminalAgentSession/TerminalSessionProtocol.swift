import Foundation
import AgentAtom

/// A protocol representing an `AgenticSessionProtocol` that is driven by a terminal CLI subprocess.
///
/// Any terminal session package or custom provider conforming to `TerminalSessionProtocol` can be
/// plugged directly into `TerminalAgentSession` or registered dynamically.
public protocol TerminalSessionProtocol: AgenticSessionProtocol {
    /// The configuration describing the binary path, arguments, working directory, and metadata.
    var configuration: TerminalAgentConfiguration { get }

    /// Clears execution metadata and conversation context from memory without terminating the underlying in-memory process.
    func clearMemory()

    /// Purges all memory, terminates any persistent subprocesses, and releases system resources.
    func purgeMemory()
}

extension TerminalSessionProtocol {
    public func clearMemory() {}
    public func purgeMemory() {
        clearMemory()
    }

    /// Default implementation for `respond`: delegates directly to `stream` with a no-op yield handler.
    public func respond(
        to input: String,
        instructions: String,
        schema: JSONString,
        for operation: ObjectIdentifier
    ) async -> Result<String, AgenticError> {
        await stream(to: input, instructions: instructions, schema: schema, for: operation, yield: { _ in })
    }
}

/// A provider descriptor that can instantiate a `TerminalSessionProtocol` given a configuration.
public struct TerminalProvider: Sendable {
    public let name: String
    public let defaultExecutablePath: String
    private let factory: @Sendable (TerminalAgentConfiguration) -> (any TerminalSessionProtocol)?

    public init(
        name: String,
        defaultExecutablePath: String,
        factory: @escaping @Sendable (TerminalAgentConfiguration) -> (any TerminalSessionProtocol)?
    ) {
        self.name = name
        self.defaultExecutablePath = defaultExecutablePath
        self.factory = factory
    }

    /// Convenience initializer to create a provider for ANY command-line agent tool (e.g. `muse`, `claude`, `ollama`).
    public static func generic(
        name: String,
        executablePath: String,
        argumentBuilder: (@Sendable (String, String, JSONString, TerminalAgentConfiguration) -> CLIArguments)? = nil
    ) -> TerminalProvider {
        TerminalProvider(name: name, defaultExecutablePath: executablePath) { config in
            GenericTerminalSession(configuration: config, argumentBuilder: argumentBuilder)
        }
    }

    /// Attempts to build a session instance using this provider with the given configuration.
    public func createSession(configuration: TerminalAgentConfiguration) -> (any TerminalSessionProtocol)? {
        factory(configuration)
    }
}

// MARK: - Convenience extensions for Spec, ModelledSpec, and Decodable execution

extension AgenticSessionProtocol {
    /// Executes any standard `Spec` and returns the resulting raw response string.
    ///
    /// Usage:
    /// ```swift
    /// let session = TerminalAgentSession()!
    /// let resultString = try await session.executeSpec(anySpec)
    /// ```
    public func executeSpec<S: Spec>(_ spec: S) async throws -> String {
        let op = AgenticOperation(spec: spec, session: self)
        return try await op.execute().get()
    }

    /// Executes any standard `Spec` with failable semantics and returns the resulting response string.
    public func executeFailableSpec<S: Spec>(_ spec: S) async throws -> String {
        let op = FailableAgenticOperation(spec: spec, session: self)
        return try await op.execute().get()
    }

    /// Executes a `ModelledSpec` and automatically decodes the structured output into `Spec.Output`.
    ///
    /// Usage:
    /// ```swift
    /// let session = TerminalAgentSession()!
    /// let spec = ShekharJokeGeneratorSpec(...)
    /// let output = try await session.execute(spec)
    /// ```
    public func execute<S: ModelledSpec>(_ spec: S) async throws -> S.Output {
        let op = AgenticOperation(spec: spec, session: self)
        let jsonString = try await op.execute().get()
        guard let data = jsonString.data(using: .utf8) else {
            throw AgenticError.operationFailed(reason: "Failed to read string data from session output.")
        }
        do {
            return try JSONDecoder().decode(S.Output.self, from: data)
        } catch {
            throw AgenticError(action: "Failed to decode \(S.Output.self)", error: error)
        }
    }

    /// Executes a `ModelledSpec` with failable semantics and decodes the result.
    public func executeFailable<S: ModelledSpec>(_ spec: S) async throws -> S.Output {
        let op = FailableAgenticOperation(spec: spec, session: self)
        let jsonString = try await op.execute().get()
        guard let data = jsonString.data(using: .utf8) else {
            throw AgenticError.operationFailed(reason: "Failed to read string data from session output.")
        }
        do {
            return try JSONDecoder().decode(S.Output.self, from: data)
        } catch {
            throw AgenticError(action: "Failed to decode \(S.Output.self)", error: error)
        }
    }

    /// Directly requests a typed Decodable response given an Encodable input, instructions, and an operation identifier.
    public func respond<Input: Encodable & Sendable, Output: Decodable & Sendable>(
        input: Input,
        instructions: String,
        outputType: Output.Type = Output.self,
        for operation: ObjectIdentifier = ObjectIdentifier(UUID() as AnyObject)
    ) async throws -> Output {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let inputData = try? encoder.encode(input),
              let inputText = String(data: inputData, encoding: .utf8) else {
            throw AgenticError.operationFailed(reason: "Failed to encode input into JSON.")
        }

        guard let schema = JSONSchema(Output.self) else {
            throw AgenticError.operationFailed(reason: "Failed to derive JSONSchema for \(Output.self).")
        }

        guard let schemaJSON = JSONString(schema.rawValue) else {
            throw AgenticError.operationFailed(reason: "Invalid JSON schema derived for \(Output.self).")
        }

        let responseText = try await self.respond(
            to: inputText,
            instructions: instructions,
            schema: schemaJSON,
            for: operation
        ).get()

        guard let data = responseText.data(using: .utf8) else {
            throw AgenticError.operationFailed(reason: "Invalid UTF8 in response string.")
        }
        do {
            return try JSONDecoder().decode(Output.self, from: data)
        } catch {
            throw AgenticError(action: "Failed to decode \(Output.self)", error: error)
        }
    }
}

