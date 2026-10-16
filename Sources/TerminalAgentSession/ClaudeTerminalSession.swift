import Foundation
import AgentAtom

/// An `AgentAtom.AgenticSessionProtocol` implementation driving Claude Code CLI (`claude`).
public final class ClaudeTerminalSession: TerminalSessionProtocol {
    public var configuration: TerminalAgentConfiguration { engine.configuration }
    public var executionMetadata: [AgenticExecutionMetadata] { engine.executionMetadata }

    public typealias Configuration = TerminalAgentConfiguration
    private let engine: TerminalSessionEngine

    public init?(configuration: Configuration = Configuration(executablePath: "claude", persistenceMode: .ephemeral)) {
        var adjusted = configuration
        // Claude Code print mode execution requires ephemeral mode to pass prompt arguments
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
        var arguments = CLIArguments(["-p"])
        arguments.append(option: "--output-format", value: "stream-json")
        arguments.append(option: "--json-schema", value: schema.rawValue)
        arguments.append(flag: "--bare")
        arguments.append(option: "--model", optionalValue: configuration.model)
        arguments += configuration.extraArguments
        arguments.append("\(instructions)\n\nInput:\n\(input)")

        let request = TerminalSessionEngine.StreamExecutionRequest(
            arguments: arguments,
            operation: operation,
            defaultModel: "claude",
            lineHandler: { line in
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    let isJSON = line.hasPrefix("{") && line.hasSuffix("}")
                    return (extracted: isJSON ? line : nil, yieldChunk: line)
                }

                var yieldChunk: String?
                var extracted: String?

                let type = (obj["type"] as? String) ?? ""

                if type == "text" || type == "delta" || type == "stream_event" {
                    if let content = obj["content"] as? String {
                        yieldChunk = content
                    } else if let delta = obj["delta"] as? [String: Any], let text = delta["text"] as? String {
                        yieldChunk = text
                    } else if let text = obj["text"] as? String {
                        yieldChunk = text
                    }
                } else if type == "result" || type == "completed" {
                    if let structured = obj["structured_output"] {
                        if let structuredData = try? JSONSerialization.data(withJSONObject: structured, options: [.sortedKeys]) {
                            extracted = String(decoding: structuredData, as: UTF8.self)
                        }
                    } else if let res = obj["result"] as? String {
                        extracted = res
                    } else if let resObj = obj["result"] {
                        if let resData = try? JSONSerialization.data(withJSONObject: resObj, options: [.sortedKeys]) {
                            extracted = String(decoding: resData, as: UTF8.self)
                        }
                    }
                }
                return (extracted: extracted, yieldChunk: yieldChunk)
            }
        )
        return await engine.runStreamedExecution(request: request, yield: yield)
    }
}
