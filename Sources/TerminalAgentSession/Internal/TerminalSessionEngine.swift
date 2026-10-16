import Foundation
import Synchronization
import AgentAtom

/// An internal base engine that provides shared process execution, metadata tracking, single-flight concurrency,
/// and conversation context tracking across sequential executions.
final class TerminalSessionEngine: Sendable {
    let configuration: TerminalAgentConfiguration
    let runner: TerminalProcessRunner
    private let state = Mutex(State())

    struct State: Sendable {
        var isBusy = false
        var records: [AgenticExecutionMetadata] = []
        var activeConversationID: String?
        var managedProcess: TerminalProcessRunner.ManagedProcess?
    }

    var executionMetadata: [AgenticExecutionMetadata] {
        state.withLock { $0.records }
    }

    var activeConversationID: String? {
        state.withLock { $0.activeConversationID }
    }

    init?(configuration: TerminalAgentConfiguration, runner: TerminalProcessRunner = TerminalProcessRunner()) {
        guard let resolvedURL = runner.resolveExecutable(
            named: configuration.executablePath,
            additionalSearchPaths: configuration.additionalSearchPaths
        ) else {
            return nil
        }
        var updated = configuration
        updated.resolvedURL = resolvedURL
        self.configuration = updated
        self.runner = runner
        if let initialID = configuration.conversationID {
            state.withLock { $0.activeConversationID = initialID }
        }
    }

    /// Sets or updates the active conversation ID.
    func setConversationID(_ id: String?) {
        state.withLock { $0.activeConversationID = id }
    }

    /// Clears execution metadata without terminating the active in-memory process.
    func clearMemory() {
        state.withLock {
            $0.records.removeAll()
        }
    }

    /// Purges all session memory, terminates any running in-memory process, and resets all engine state.
    func purgeMemory() {
        state.withLock {
            $0.records.removeAll()
            $0.activeConversationID = nil
            $0.managedProcess?.terminate()
            $0.managedProcess = nil
        }
    }

    /// Executes CLI arguments with single-run admission, timing metadata recording, and streaming callback.
    func execute(
        arguments: CLIArguments,
        operation: ObjectIdentifier,
        defaultModel: String,
        yield: (String) async -> Void
    ) async throws -> TerminalProcessRunner.ExecutionResult {
        guard !Task.isCancelled else { throw AgenticError.cancelled }

        let admitted = state.withLock { state -> Bool in
            guard !state.isBusy else { return false }
            state.isBusy = true
            return true
        }
        guard admitted else { throw AgenticError.busy }

        let startTime = ContinuousClock().now
        let executionID = UUID()

        defer {
            let record = AgenticExecutionMetadata(
                operationID: operation,
                executionID: executionID,
                modelIdentifier: configuration.metadata.contains(.modelIdentifier) ? (configuration.model ?? defaultModel) : nil,
                duration: configuration.metadata.contains(.duration) ? startTime.duration(to: ContinuousClock().now) : nil,
                promptTokens: nil,
                completionTokens: nil
            )
            state.withLock { state in
                if configuration.memoryRetentionPolicy == .clear {
                    state.records.removeAll()
                } else {
                    state.records.append(record)
                }
                state.isBusy = false
            }
        }

        guard let executableURL = configuration.resolvedURL else {
            throw AgenticError.operationFailed(reason: "Executable not resolved at '\(configuration.executablePath)'")
        }

        let launchRequest = TerminalProcessRunner.LaunchRequest(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: configuration.workingDirectory
        )

        switch configuration.persistenceMode {
        case .persistentStdio:
            return try await executeWithPersistentProcess(request: launchRequest, yield: yield)
        case .daemon, .ephemeral:
            return try await runner.streamLines(request: launchRequest, yield: yield)
        }
    }

    private func executeWithPersistentProcess(
        request: TerminalProcessRunner.LaunchRequest,
        yield: (String) async -> Void
    ) async throws -> TerminalProcessRunner.ExecutionResult {
        // Reuse existing running in-memory process, or spawn and retain a new one
        let process: TerminalProcessRunner.ManagedProcess = try state.withLock { state in
            if let existing = state.managedProcess, existing.isRunning {
                return existing
            }
            let spawnRequest = TerminalProcessRunner.LaunchRequest(
                executableURL: request.executableURL,
                arguments: configuration.extraArguments,
                currentDirectoryURL: configuration.workingDirectory
            )
            let spawned = try runner.spawnProcess(request: spawnRequest)
            state.managedProcess = spawned
            return spawned
        }

        // If the process is not running (e.g. CLI that ran to completion immediately or exited), spawn fresh via streamLines
        if !process.isRunning {
            state.withLock { $0.managedProcess = nil }
            return try await runner.streamLines(request: request, yield: yield)
        }

        let inputPrompt = request.arguments.last ?? ""
        if let inputData = (inputPrompt + "\n").data(using: .utf8) {
            try? process.stdinHandle.write(contentsOf: inputData)
        }

        let stdout = try await process.readLinesUntil(
            stopCondition: { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains("\"type\":\"result\"") || trimmed.contains("\"type\":\"completed\"") || trimmed.contains("\"result\":") {
                    return true
                }
                if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) && !trimmed.contains("\"type\":\"text\"") && !trimmed.contains("\"type\":\"delta\"") && !trimmed.contains("\"delta\":") {
                    return true
                }
                return false
            },
            onCancel: { process.terminate() },
            yield: yield
        )

        // If process exited during or after read, clear it so next call respawns cleanly
        if !process.isRunning {
            state.withLock { $0.managedProcess = nil }
        }

        let exitCode = process.terminationStatus ?? 0
        return TerminalProcessRunner.ExecutionResult(
            stdout: stdout,
            stderr: "",
            exitCode: exitCode
        )
    }

    /// Strongly typed parameters configuring streamed execution through the session engine.
    struct StreamExecutionRequest: Sendable {
        let arguments: CLIArguments
        let operation: ObjectIdentifier
        let defaultModel: String
        let lineHandler: @Sendable (String) async -> (extracted: String?, yieldChunk: String?)
        let fallbackExtractor: (@Sendable (TerminalProcessRunner.ExecutionResult) -> String?)?

        init(
            arguments: CLIArguments,
            operation: ObjectIdentifier,
            defaultModel: String,
            lineHandler: @escaping @Sendable (String) async -> (extracted: String?, yieldChunk: String?),
            fallbackExtractor: (@Sendable (TerminalProcessRunner.ExecutionResult) -> String?)? = nil
        ) {
            self.arguments = arguments
            self.operation = operation
            self.defaultModel = defaultModel
            self.lineHandler = lineHandler
            self.fallbackExtractor = fallbackExtractor
        }
    }

    /// Shared pipeline that executes CLI arguments, processes streamed output line-by-line,
    /// checks exit codes, and extracts final structured output cleanly.
    func runStreamedExecution(
        request: StreamExecutionRequest,
        yield: @Sendable (String) async -> Void
    ) async -> Result<String, AgenticError> {
        do {
            let extractedMutex = Mutex<String?>(nil)

            let result = try await execute(
                arguments: request.arguments,
                operation: request.operation,
                defaultModel: request.defaultModel,
                yield: { line in
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let (extracted, yieldChunk) = await request.lineHandler(trimmed)
                    if let chunk = yieldChunk {
                        await yield(chunk)
                    }
                    if let extracted = extracted {
                        extractedMutex.withLock { $0 = extracted }
                    }
                }
            )

            guard result.exitCode == 0 else {
                return .failure(AgenticError(executablePath: configuration.executablePath, exitCode: result.exitCode, stderr: result.stderr))
            }

            if let fallbackResult = request.fallbackExtractor?(result) {
                return .success(fallbackResult)
            }

            if let finalOutput = extractedMutex.withLock({ $0 }), !finalOutput.isEmpty {
                return .success(finalOutput)
            }

            let trimmedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedStdout.isEmpty {
                return .success(trimmedStdout)
            }

            return .failure(.generationFailed(reason: "\(configuration.executablePath) produced no output."))
        } catch {
            return .failure(AgenticError(error))
        }
    }
}

