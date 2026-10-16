import Foundation
import Synchronization
import AgentAtom

/// An internal process runner instance that executes commands and streams lines.
///
/// Handles execution across three distinct persistence modes configured by `TerminalAgentConfiguration`:
/// 1. `.persistentStdio`: Keeps a single long-running subprocess active in memory across multiple turns,
///    reusing stdin/stdout pipes to eliminate expensive process creation overhead.
/// 2. `.daemon`: Connects to pre-existing background agent server/daemon sockets or protocols.
/// 3. `.ephemeral`: Executes short-lived processes with isolated process lifecycles per turn.
final class TerminalProcessRunner: Sendable {
    struct ExecutionResult: Sendable {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    init() {}

    /// A long-running process managed by the session in memory.
    ///
    /// Kept alive across turns in `.persistentStdio` mode. Retains open pipes for continuous
    /// streaming interaction until `purgeMemory()` or session deinitialization.
    final class ManagedProcess: Sendable {
        private let state: Mutex<ProcessState>

        private struct ProcessState {
            let process: Process
            let stdinPipe: Pipe
            let stdoutPipe: Pipe
            let stderrPipe: Pipe
            var pendingStdout: String = ""
        }

        init(process: Process, stdinPipe: Pipe, stdoutPipe: Pipe, stderrPipe: Pipe) {
            self.state = Mutex(ProcessState(
                process: process,
                stdinPipe: stdinPipe,
                stdoutPipe: stdoutPipe,
                stderrPipe: stderrPipe
            ))
        }

        var isRunning: Bool {
            state.withLock { $0.process.isRunning }
        }

        var stdinHandle: FileHandle {
            state.withLock { $0.stdinPipe.fileHandleForWriting }
        }

        var stdoutHandle: FileHandle {
            state.withLock { $0.stdoutPipe.fileHandleForReading }
        }

        var stderrHandle: FileHandle {
            state.withLock { $0.stderrPipe.fileHandleForReading }
        }

        var terminationStatus: Int32? {
            state.withLock {
                $0.process.isRunning ? nil : $0.process.terminationStatus
            }
        }

        /// Reads output lines from stdout until the stop condition is satisfied, preserving any remainder in `pendingStdout`.
        func readLinesUntil(
            stopCondition: @Sendable (String) -> Bool,
            onCancel: @Sendable () -> Void,
            yield: (String) async -> Void
        ) async throws -> String {
            var emittedLines: [String] = []

            while true {
                if Task.isCancelled {
                    onCancel()
                    throw AgenticError.cancelled
                }

                // First check if pendingStdout already has a complete line
                var extractedLine: String?
                state.withLock { state in
                    if let newlineIndex = state.pendingStdout.firstIndex(of: "\n") {
                        let line = String(state.pendingStdout[..<newlineIndex])
                        state.pendingStdout.removeSubrange(...newlineIndex)
                        extractedLine = line
                    }
                }

                if let line = extractedLine {
                    emittedLines.append(line)
                    await yield(line)
                    if stopCondition(line) {
                        return emittedLines.joined(separator: "\n")
                    }
                    continue
                }

                // If no complete line in pending buffer, read more from pipe
                let chunk = stdoutHandle.availableData
                guard !chunk.isEmpty else { break }

                let text = String(decoding: chunk, as: UTF8.self)
                state.withLock { state in
                    state.pendingStdout.append(text)
                }
            }

            let leftover = state.withLock { state -> String in
                let rest = state.pendingStdout
                state.pendingStdout = ""
                return rest
            }
            if !leftover.isEmpty {
                emittedLines.append(leftover)
                await yield(leftover)
            }

            return emittedLines.joined(separator: "\n")
        }

        func terminate() {
            state.withLock {
                if $0.process.isRunning {
                    $0.process.terminate()
                }
            }
        }

        deinit {
            terminate()
        }
    }

    /// A strongly-typed request encapsulation describing how a subprocess should be launched.
    struct LaunchRequest: Sendable {
        let executableURL: URL
        let arguments: CLIArguments
        let environment: [String: String]?
        let currentDirectoryURL: URL?

        init(
            executableURL: URL,
            arguments: CLIArguments,
            environment: [String: String]? = nil,
            currentDirectoryURL: URL? = nil
        ) {
            self.executableURL = executableURL
            self.arguments = arguments
            self.environment = environment
            self.currentDirectoryURL = currentDirectoryURL
        }
    }

    /// Spawns a long-running process with persistent stdio pipes.
    func spawnProcess(request: LaunchRequest) throws -> ManagedProcess {
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = request.executableURL
        process.arguments = request.arguments.rawTokens
        if let environment = request.environment { process.environment = environment }
        if let currentDirectoryURL = request.currentDirectoryURL { process.currentDirectoryURL = currentDirectoryURL }
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw mapLaunchError(error, path: request.executableURL.path)
        }

        return ManagedProcess(
            process: process,
            stdinPipe: stdinPipe,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )
    }

    /// Spawns a process and asynchronously returns lines as they are produced on standard output.
    func streamLines(
        request: LaunchRequest,
        yield: (String) async -> Void
    ) async throws -> ExecutionResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        configure(
            process: process,
            executableURL: request.executableURL,
            arguments: request.arguments.rawTokens,
            environment: request.environment,
            currentDirectoryURL: request.currentDirectoryURL,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )

        do {
            try process.run()
        } catch {
            throw mapLaunchError(error, path: request.executableURL.path)
        }

        let stderrTask = Task { readStream(from: stderrPipe.fileHandleForReading) }
        let stdout = try await readAndStreamLines(
            from: stdoutPipe.fileHandleForReading,
            onCancel: { process.terminate() },
            yield: yield
        )

        process.waitUntilExit()
        let stderr = await stderrTask.value

        return ExecutionResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }

    /// Resolves executable in system PATH and additional search paths if url does not exist directly.
    func resolveExecutable(named name: String, additionalSearchPaths: [String] = []) -> URL? {
        if isExplicitPath(name) {
            return searchExtensions(basePath: name)
        }
        return searchSystemPath(named: name, additionalSearchPaths: additionalSearchPaths)
    }

    // MARK: - Private Decomposed Helpers

    private func configure(
        process: Process,
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        currentDirectoryURL: URL?,
        stdoutPipe: Pipe,
        stderrPipe: Pipe
    ) {
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectoryURL { process.currentDirectoryURL = currentDirectoryURL }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
    }

    private func readStream(from handle: FileHandle) -> String {
        let data = handle.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    func readAndStreamLines(
        from handle: FileHandle,
        stopCondition: @Sendable (String) -> Bool = { _ in false },
        onCancel: @Sendable () -> Void = {},
        yield: (String) async -> Void
    ) async throws -> String {
        var emittedLines: [String] = []
        var pendingStdout = ""

        while true {
            if Task.isCancelled {
                onCancel()
                throw AgenticError.cancelled
            }

            let chunk = handle.availableData
            guard !chunk.isEmpty else { break }

            let text = String(decoding: chunk, as: UTF8.self)
            pendingStdout.append(text)

            var shouldStop = false
            while let newlineIndex = pendingStdout.firstIndex(of: "\n") {
                let line = String(pendingStdout[..<newlineIndex])
                pendingStdout.removeSubrange(...newlineIndex)
                emittedLines.append(line)
                await yield(line)
                if stopCondition(line) {
                    shouldStop = true
                    break
                }
            }
            if shouldStop { break }
        }

        if !pendingStdout.isEmpty {
            emittedLines.append(pendingStdout)
            await yield(pendingStdout)
        }

        return emittedLines.joined(separator: "\n")
    }

    private func mapLaunchError(_ error: Error, path: String) -> AgenticError {
        AgenticError(error)
    }

    private var executableExtensions: [String] {
        #if os(Windows)
        ["", ".exe", ".cmd", ".bat"]
        #else
        [""]
        #endif
    }

    private var pathSeparator: Character {
        #if os(Windows)
        ";"
        #else
        ":"
        #endif
    }

    private var defaultSystemPath: String {
        #if os(Windows)
        "C:\\Windows\\System32;C:\\Windows"
        #else
        "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
        #endif
    }

    private func isExplicitPath(_ name: String) -> Bool {
        name.hasPrefix("/") || name.hasPrefix("./") || (name.count > 1 && name.contains(":"))
    }

    private func searchExtensions(basePath: String) -> URL? {
        for ext in executableExtensions {
            let candidate = ext.isEmpty ? basePath : basePath + ext
            let url = URL(fileURLWithPath: candidate)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func searchSystemPath(named name: String, additionalSearchPaths: [String] = []) -> URL? {
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? defaultSystemPath
        let envSearchPaths = envPath.split(separator: pathSeparator).map(String.init)
        let searchPaths = additionalSearchPaths + envSearchPaths
        for searchPath in searchPaths {
            for ext in executableExtensions {
                let fullName = ext.isEmpty ? name : name + ext
                let candidate = URL(fileURLWithPath: searchPath).appendingPathComponent(fullName)
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }
}
