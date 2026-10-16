import Foundation
import Synchronization
import AgentAtom

/// An `AgentAtom.AgenticSessionProtocol` implementation driving Antigravity CLI (`agy`).
public final class AntigravityTerminalSession: TerminalSessionProtocol {
    public var configuration: TerminalAgentConfiguration { engine.configuration }
    public var executionMetadata: [AgenticExecutionMetadata] { engine.executionMetadata }

    public typealias Configuration = TerminalAgentConfiguration
    private let engine: TerminalSessionEngine

    public init?(configuration: Configuration = Configuration(executablePath: "agy", persistenceMode: .ephemeral)) {
        var adjusted = configuration
        // Antigravity noninteractive batch/stream CLI execution requires ephemeral mode to pass prompt arguments
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
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("agy_\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return .failure(AgenticError(action: "Failed to create temporary directory", error: error))
        }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let schemaFile = tempDir.appendingPathComponent("schema.json")
        do {
            try schema.rawValue.write(to: schemaFile, atomically: true, encoding: .utf8)
        } catch {
            return .failure(AgenticError(action: "Failed to write schema", error: error))
        }

        var arguments = CLIArguments()
        arguments.append(option: "--output-format", value: "stream-json")
        arguments.append(option: "--json-schema", value: schemaFile.path)
        arguments.append(flag: "--dangerously-skip-permissions")
        arguments.append(flag: "--disable-slash-commands")
        arguments.append(option: "--model", optionalValue: configuration.model)
        arguments += configuration.extraArguments
        arguments.append("--print=\(instructions)\n\nInput:\n\(input)")

        let reportedFailure = Mutex(false)
        let request = TerminalSessionEngine.StreamExecutionRequest(
            arguments: arguments,
            operation: operation,
            defaultModel: "agy",
            lineHandler: { line in
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    let isJSON = line.hasPrefix("{") && line.hasSuffix("}")
                    return (extracted: isJSON ? line : nil, yieldChunk: line)
                }

                var yieldChunk: String?
                var extracted: String?

                let type = (obj["type"] as? String) ?? (obj["event"] as? String) ?? ""

                if type == "text" || type == "delta" {
                    if let content = obj["content"] as? String {
                        yieldChunk = content
                    } else if let delta = obj["delta"] as? [String: Any], let text = delta["text"] as? String {
                        yieldChunk = text
                    }
                } else if type == "step_update", let step = obj["step_update"] as? [String: Any] {
                    if let text = step["text_delta"] as? String, !text.isEmpty {
                        yieldChunk = text
                    }
                } else if type == "result" || type == "completed" {
                    let resultDict = (obj["result"] as? [String: Any]) ?? obj
                    let status = (resultDict["status"] as? String) ?? (obj["status"] as? String)
                    let failed = (status.map { $0.lowercased() != "success" } ?? false)
                        || (resultDict["is_error"] as? Bool == true) || (obj["is_error"] as? Bool == true)
                    if failed {
                        reportedFailure.withLock { $0 = true }
                        return (extracted: nil, yieldChunk: nil)
                    }
                    if let structured = resultDict["structured_output"] {
                        if let structuredData = try? JSONSerialization.data(withJSONObject: structured, options: [.sortedKeys]) {
                            extracted = String(decoding: structuredData, as: UTF8.self)
                        }
                    } else if let res = resultDict["response"] as? String {
                        extracted = res
                    } else if let resObj = resultDict["response"] {
                        if let resData = try? JSONSerialization.data(withJSONObject: resObj, options: [.sortedKeys]) {
                            extracted = String(decoding: resData, as: UTF8.self)
                        }
                    }
                }
                return (extracted: extracted, yieldChunk: yieldChunk)
            }
        )
        let result = await engine.runStreamedExecution(request: request, yield: yield)
        if case .success = result, reportedFailure.withLock({ $0 }) {
            return .failure(.generationFailed(reason: "Antigravity reported an unsuccessful result."))
        }
        return result
    }
}
