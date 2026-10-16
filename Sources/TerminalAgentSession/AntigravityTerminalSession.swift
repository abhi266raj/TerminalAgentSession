import Foundation
import AgentAtom

/// An `AgentAtom.AgenticSessionProtocol` implementation driving Antigravity CLI (`agy`).
public final class AntigravityTerminalSession: TerminalSessionProtocol {
    public var configuration: TerminalAgentConfiguration { engine.configuration }
    public var executionMetadata: [AgenticExecutionMetadata] { engine.executionMetadata }

    public typealias Configuration = TerminalAgentConfiguration
    private let engine: TerminalSessionEngine

    public init?(configuration: Configuration = Configuration(executablePath: "agy")) {
        guard let engine = TerminalSessionEngine(configuration: configuration) else { return nil }
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
        var arguments = CLIArguments()
        arguments.append(option: "--output-format", value: "stream-json")
        arguments.append(option: "--json-schema", value: schema.rawValue)
        arguments.append(flag: "--dangerously-skip-permissions")
        arguments.append(option: "--model", optionalValue: configuration.model)
        arguments += configuration.extraArguments
        arguments.append("\(instructions)\n\nInput:\n\(input)")

        let request = TerminalSessionEngine.StreamExecutionRequest(
            arguments: arguments,
            operation: operation,
            defaultModel: "agy",
            lineHandler: { line in
                if let data = line.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    var yieldChunk: String?
                    var extracted: String?
                    if let type = obj["type"] as? String {
                        if type == "text" || type == "delta", let content = obj["content"] as? String {
                            yieldChunk = content
                        } else if type == "result" || type == "completed" {
                            if let res = obj["response"] as? String {
                                extracted = res
                            } else if let resObj = obj["response"] {
                                if let resData = try? JSONSerialization.data(withJSONObject: resObj, options: [.sortedKeys]) {
                                    extracted = String(decoding: resData, as: UTF8.self)
                                }
                            }
                        }
                    }
                    return (extracted: extracted, yieldChunk: yieldChunk)
                } else {
                    let isJSON = line.hasPrefix("{") && line.hasSuffix("}")
                    return (extracted: isJSON ? line : nil, yieldChunk: line)
                }
            }
        )
        return await engine.runStreamedExecution(request: request, yield: yield)
    }
}
