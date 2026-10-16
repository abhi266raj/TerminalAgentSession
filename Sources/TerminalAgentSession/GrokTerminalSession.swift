import Foundation
import AgentAtom

/// An `AgentAtom.AgenticSessionProtocol` implementation driving Grok CLI (`grok`).
public final class GrokTerminalSession: TerminalSessionProtocol {
    public var configuration: TerminalAgentConfiguration { engine.configuration }
    public var executionMetadata: [AgenticExecutionMetadata] { engine.executionMetadata }

    public typealias Configuration = TerminalAgentConfiguration
    private let engine: TerminalSessionEngine

    public init?(configuration: Configuration = Configuration(executablePath: "grok")) {
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
        arguments.append(option: "--output-format", value: "streaming-messages-json")
        arguments.append(option: "--schema", value: schema.rawValue)
        arguments.append(option: "--model", optionalValue: configuration.model)
        arguments += configuration.extraArguments
        arguments.append("\(instructions)\n\nInput:\n\(input)")

        let request = TerminalSessionEngine.StreamExecutionRequest(
            arguments: arguments,
            operation: operation,
            defaultModel: "grok",
            lineHandler: { line in
                if let data = line.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    var yieldChunk: String?
                    var extracted: String?
                    if let delta = obj["delta"] as? String {
                        yieldChunk = delta
                    } else if let content = obj["content"] as? String {
                        yieldChunk = content
                    }
                    if let finalResult = obj["result"] as? String {
                        extracted = finalResult
                    } else if let finalObj = obj["result"] {
                        if let resData = try? JSONSerialization.data(withJSONObject: finalObj, options: [.sortedKeys]) {
                            extracted = String(decoding: resData, as: UTF8.self)
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
