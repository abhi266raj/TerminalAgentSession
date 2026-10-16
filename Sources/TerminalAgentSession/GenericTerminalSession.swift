import Foundation
import AgentAtom

/// A generic, configurable terminal CLI session that can drive ANY command-line agent tool (e.g. `muse`, `claude`, `ollama`).
///
/// Use this whenever you want to plug in a new or custom CLI agent without creating a custom class or package:
/// ```swift
/// let museSession = GenericTerminalSession(executablePath: "muse")!
/// ```
public final class GenericTerminalSession: TerminalSessionProtocol {
    public var configuration: TerminalAgentConfiguration { engine.configuration }
    public var executionMetadata: [AgenticExecutionMetadata] { engine.executionMetadata }

    public typealias Configuration = TerminalAgentConfiguration
    private let engine: TerminalSessionEngine
    private let argumentBuilder: @Sendable (String, String, JSONString, TerminalAgentConfiguration) -> CLIArguments

    public init?(
        configuration: Configuration,
        argumentBuilder: (@Sendable (String, String, JSONString, TerminalAgentConfiguration) -> CLIArguments)? = nil
    ) {
        guard let engine = TerminalSessionEngine(configuration: configuration) else { return nil }
        self.engine = engine
        self.argumentBuilder = argumentBuilder ?? { input, instructions, schema, config in
            var args = config.extraArguments
            args.append(option: "--model", optionalValue: config.model)
            args.append("\(instructions)\n\nInput:\n\(input)")
            return args
        }
    }

    public func clearMemory() {
        engine.clearMemory()
    }

    public func purgeMemory() {
        engine.purgeMemory()
    }

    public convenience init?(
        executablePath: String,
        model: String? = nil,
        workingDirectory: URL? = nil,
        extraArguments: CLIArguments = [],
        argumentBuilder: (@Sendable (String, String, JSONString, TerminalAgentConfiguration) -> CLIArguments)? = nil
    ) {
        self.init(
            configuration: TerminalAgentConfiguration(
                executablePath: executablePath,
                model: model,
                workingDirectory: workingDirectory,
                extraArguments: extraArguments
            ),
            argumentBuilder: argumentBuilder
        )
    }

    public convenience init?(
        executablePath: String,
        model: String? = nil,
        workingDirectory: URL? = nil,
        extraArguments: [String],
        argumentBuilder: (@Sendable (String, String, JSONString, TerminalAgentConfiguration) -> CLIArguments)? = nil
    ) {
        self.init(
            executablePath: executablePath,
            model: model,
            workingDirectory: workingDirectory,
            extraArguments: CLIArguments(extraArguments),
            argumentBuilder: argumentBuilder
        )
    }


    public func stream(
        to input: String,
        instructions: String,
        schema: JSONString,
        for operation: ObjectIdentifier,
        yield: @Sendable (String) async -> Void
    ) async -> Result<String, AgenticError> {
        let prompt = "\(instructions)\n\nInput:\n\(input)"
        let args = argumentBuilder(input, prompt, schema, configuration)
        let request = TerminalSessionEngine.StreamExecutionRequest(
            arguments: args,
            operation: operation,
            defaultModel: configuration.executablePath,
            lineHandler: { line in
                let isJSON = (line.hasPrefix("{") && line.hasSuffix("}")) ||
                             (line.hasPrefix("[") && line.hasSuffix("]"))
                return (extracted: isJSON ? line : nil, yieldChunk: line)
            }
        )
        return await engine.runStreamedExecution(request: request, yield: yield)
    }
}
