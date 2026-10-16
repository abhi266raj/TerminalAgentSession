import Foundation
import AgentAtom

/// An `AgentAtom.AgenticSessionProtocol` implementation driving Codex CLI (`codex`).
public final class CodexTerminalSession: TerminalSessionProtocol {
    public var configuration: TerminalAgentConfiguration { engine.configuration }
    public var executionMetadata: [AgenticExecutionMetadata] { engine.executionMetadata }

    public typealias Configuration = TerminalAgentConfiguration
    private let engine: TerminalSessionEngine

    public init?(configuration: Configuration = Configuration(executablePath: "codex", persistenceMode: .ephemeral)) {
        var adjusted = configuration
        // Codex batch CLI execution writes to a temporary file via -o and exits, so it requires ephemeral mode
        if case .persistentStdio = configuration.persistenceMode {
            adjusted.persistenceMode = .ephemeral
        }
        guard let engine = TerminalSessionEngine(configuration: adjusted) else { return nil }
        self.engine = engine
    }

    public func clearMemory() {
        engine.clearMemory()
    }

    public func purgeMemory() {
        engine.purgeMemory()
    }

    public func stream(
        to input: String,
        instructions: String,
        schema: JSONString,
        for operation: ObjectIdentifier,
        yield: @Sendable (String) async -> Void
    ) async -> Result<String, AgenticError> {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("codex_\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return .failure(AgenticError(action: "Failed to create temporary directory", error: error))
        }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let schemaFile = tempDir.appendingPathComponent("schema.json")
        let outputFile = tempDir.appendingPathComponent("output.json")

        do {
            try schema.rawValue.write(to: schemaFile, atomically: true, encoding: .utf8)
        } catch {
            return .failure(AgenticError(action: "Failed to write output schema", error: error))
        }

        var arguments = CLIArguments(["exec"])
        arguments.append(option: "--model", optionalValue: configuration.model)
        arguments.append(option: "--output-schema", value: schemaFile.path)
        arguments.append(option: "-o", value: outputFile.path)
        arguments += configuration.extraArguments
        arguments.append("\(instructions)\n\nInput:\n\(input)")

        let request = TerminalSessionEngine.StreamExecutionRequest(
            arguments: arguments,
            operation: operation,
            defaultModel: "codex",
            lineHandler: { line in
                (extracted: nil, yieldChunk: line)
            },
            fallbackExtractor: { _ in
                if FileManager.default.fileExists(atPath: outputFile.path),
                   let outputData = try? Data(contentsOf: outputFile),
                   let outputString = String(data: outputData, encoding: .utf8),
                   !outputString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return outputString
                }
                return nil
            }
        )
        return await engine.runStreamedExecution(request: request, yield: yield)
    }
}
