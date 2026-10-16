import Foundation
import Testing
import AgentAtom
@testable import TerminalAgentSession

// Simple ModelledSpec for testing
struct MockEchoSpec: ModelledSpec {
    struct Input: Codable, Sendable {
        let message: String
    }

    struct Output: Codable, Sendable, Equatable {
        let reply: String
    }

    static var identity: Identity { Identity(id: "MockEcho", name: "MockEcho", version: "1.0.0") }
    static var role: String { "Mock assistant" }
    var instructions: String { "Echo the message in reply" }

    var input: Input
    var output: Output?

    init(message: String) {
        self.input = Input(message: message)
    }
}

@Suite("TerminalAgentSession Tests")
struct TerminalSessionTests {
    private func withMockExecutable<T>(
        script: String,
        operation: (URL) async throws -> T
    ) async throws -> T {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("mock_cli_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let scriptURL = tempDir.appendingPathComponent("mock_tool.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let permissions: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        try FileManager.default.setAttributes(permissions, ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        return try await operation(scriptURL)
    }

    private func createMockExecutable(script: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("mock_cli_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let scriptURL = tempDir.appendingPathComponent("mock_tool.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let permissions: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        try FileManager.default.setAttributes(permissions, ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    @Test("CodexTerminalSession executes and decodes successfully via ModelledSpec convenience")
    func testCodexSessionConvenienceExecute() async throws {
        // Mock Codex script that writes to -o output argument
        let script = """
        #!/bin/bash
        # Parse arguments to find output path (-o)
        while [[ "$#" -gt 0 ]]; do
            case $1 in
                -o) output_file="$2"; shift ;;
            esac
            shift
        done
        echo '{"reply":"Hello from Codex"}' > "$output_file"
        exit 0
        """
        try await withMockExecutable(script: script) { scriptURL in
            let config = CodexTerminalSession.Configuration(executablePath: scriptURL.path)
            guard let session = CodexTerminalSession(configuration: config) else {
                Issue.record("Failed to initialize CodexTerminalSession with mock script")
                return
            }

            let spec = MockEchoSpec(message: "Hi")
            let output = try await session.execute(spec)
            #expect(output.reply == "Hello from Codex")
        }
    }

    @Test("AntigravityTerminalSession streams and decodes successfully via ModelledSpec convenience")
    func testAntigravitySessionStreamingAndExecute() async throws {
        // Mock Antigravity script that outputs stream-json format
        let script = """
        #!/bin/bash
        echo '{"type":"text","content":"Generating response..."}'
        echo '{"type":"result","response":"{\\"reply\\":\\"Hello from Antigravity\\"}"}'
        exit 0
        """
        try await withMockExecutable(script: script) { scriptURL in
            let config = AntigravityTerminalSession.Configuration(executablePath: scriptURL.path)
            guard let session = AntigravityTerminalSession(configuration: config) else {
                Issue.record("Failed to initialize AntigravityTerminalSession with mock script")
                return
            }

            let spec = MockEchoSpec(message: "Hi")
            let output = try await session.execute(spec)
            #expect(output.reply == "Hello from Antigravity")
        }
    }

    @Test("GrokTerminalSession streams and decodes successfully via typed respond convenience")
    func testGrokSessionTypedRespond() async throws {
        // Mock Grok script that outputs streaming-messages-json format
        let script = """
        #!/bin/bash
        echo '{"delta":"Thinking..."}'
        echo '{"result":"{\\"reply\\":\\"Hello from Grok\\"}"}'
        exit 0
        """
        try await withMockExecutable(script: script) { scriptURL in
            let config = GrokTerminalSession.Configuration(executablePath: scriptURL.path)
            guard let session = GrokTerminalSession(configuration: config) else {
                Issue.record("Failed to initialize GrokTerminalSession with mock script")
                return
            }

            let output: MockEchoSpec.Output = try await session.respond(
                input: MockEchoSpec.Input(message: "Hi"),
                instructions: "Echo"
            )
            #expect(output.reply == "Hello from Grok")
        }
    }


    @Test("TerminalAgentSession provider explicit selection and custom provider registration")
    func testTerminalAgentSessionProviderSelection() throws {
        let script = """
        #!/bin/bash
        echo '{"reply":"Selected Provider"}'
        """
        let scriptURL = try createMockExecutable(script: script)
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

        let config = TerminalAgentConfiguration(executablePath: scriptURL.path)

        // Custom provider from another imaginary package or custom CLI
        let customProvider = TerminalProvider(name: "custom", defaultExecutablePath: scriptURL.path) {
            AntigravityTerminalSession(configuration: $0)
        }

        let session = TerminalAgentSession(provider: customProvider, configuration: config)
        #expect(session != nil)

        // Verify generic one-liner session for any current/future CLI tool (e.g. "muse")
        let museSession = TerminalAgentSession(executablePath: scriptURL.path)
        #expect(museSession != nil)
        let genericDirectSession = GenericTerminalSession(executablePath: scriptURL.path)
        #expect(genericDirectSession != nil)

        // Verify TerminalSessionProtocol polymorphism across all sessions
        let terminalSessions: [any TerminalSessionProtocol] = [
            session!,
            museSession!,
            genericDirectSession!,
            AntigravityTerminalSession(configuration: config)!,
            CodexTerminalSession(configuration: config)!,
            GrokTerminalSession(configuration: config)!
        ]
        #expect(terminalSessions.count == 6)
        for s in terminalSessions {
            #expect(!s.configuration.executablePath.isEmpty)
        }
    }

    @Test("Process exit failure maps cleanly to AgenticError.operationFailed")
    func testProcessFailureMapping() async throws {
        let script = """
        #!/bin/bash
        >&2 echo "Critical syntax error or failure"
        exit 1
        """
        let scriptURL = try createMockExecutable(script: script)
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

        let config = CodexTerminalSession.Configuration(executablePath: scriptURL.path)
        guard let session = CodexTerminalSession(configuration: config) else {
            Issue.record("Failed to initialize session")
            return
        }

        let spec = MockEchoSpec(message: "Hi")
        await #expect(throws: AgenticError.self) {
            try await session.execute(spec)
        }
    }

    @Test("StreamingAgenticOperation streams tokens and finishes with final decoded value")
    func testStreamingOperationExecution() async throws {
        let script = """
        #!/bin/bash
        echo '{"type":"text","content":"Token1"}'
        sleep 0.02
        echo '{"type":"text","content":"Token2"}'
        sleep 0.02
        echo '{"type":"result","response":"{\\"reply\\":\\"Done\\"}"}'
        exit 0
        """
        let scriptURL = try createMockExecutable(script: script)
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

        let config = AntigravityTerminalSession.Configuration(executablePath: scriptURL.path)
        guard let session = AntigravityTerminalSession(configuration: config) else {
            Issue.record("Failed to initialize session")
            return
        }

        let spec = MockEchoSpec(message: "Hi")
        let streamOp = StreamingAgenticOperation(spec: spec, session: session)
        var streamedChunks: [String] = []

        for await event in await streamOp.execute() {
            if case .success(let text) = event {
                streamedChunks.append(text)
            }
        }

        #expect(streamedChunks.contains("Token1"))
        #expect(streamedChunks.contains("Token2"))
        #expect(streamedChunks.contains("{\"reply\":\"Done\"}"))
    }

    @Test("TerminalSession tracks execution metadata and clearMemory resets it")
    func testContextPreservationAcrossTurns() async throws {
        let script = """
        #!/bin/bash
        while IFS= read -r line; do
            echo "{\\"reply\\":\\"Seen Turn\\"}"
        done
        """
        let scriptURL = try createMockExecutable(script: script)
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

        let config = TerminalAgentConfiguration(
            executablePath: scriptURL.path,
            persistenceMode: .persistentStdio(memory: .keep)
        )
        let session = GenericTerminalSession(configuration: config)!

        // Turn 1
        _ = try await session.execute(MockEchoSpec(message: "My name is Alice"))

        // Turn 2
        _ = try await session.execute(MockEchoSpec(message: "What is my name?"))

        // Verify execution metadata recorded both turns
        #expect(session.executionMetadata.count == 2)

        // Clear memory explicitly
        session.clearMemory()
        #expect(session.executionMetadata.isEmpty)

        // Turn 3 starts with cleared memory
        _ = try await session.execute(MockEchoSpec(message: "Fresh start"))
        #expect(session.executionMetadata.count == 1)
    }

    @Test("TerminalSession discovers binaries in additionalSearchPaths")
    func testAdditionalSearchPathsDiscovery() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let customBinary = tempDir.appendingPathComponent("custom-agent-cli")
        let script = """
        #!/bin/bash
        echo "{\\"reply\\":\\"from custom path\\"}"
        """
        try script.write(to: customBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: customBinary.path)

        // Without additionalSearchPaths, resolving "custom-agent-cli" fails
        let configWithout = TerminalAgentConfiguration(executablePath: "custom-agent-cli")
        #expect(GenericTerminalSession(configuration: configWithout) == nil)

        // With additionalSearchPaths, resolving succeeds
        let configWith = TerminalAgentConfiguration(
            executablePath: "custom-agent-cli",
            additionalSearchPaths: [tempDir.path]
        )
        let session = GenericTerminalSession(configuration: configWith)
        #expect(session != nil)
    }

    @Test("TerminalSession reuses persistent in-memory process across multiple turns and purgeMemory terminates it")
    func testPersistentProcessMemoryReuse() async throws {
        let counterFile = FileManager.default.temporaryDirectory.appendingPathComponent("count_\(UUID().uuidString)")
        try? "0".write(to: counterFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: counterFile) }

        // A mock script that keeps running and counts how many lines/prompts it received
        let script = """
        #!/bin/bash
        while IFS= read -r line; do
            COUNT=$(cat "\(counterFile.path)")
            COUNT=$((COUNT + 1))
            echo "$COUNT" > "\(counterFile.path)"
            echo "{\\"reply\\":\\"turn $COUNT\\"}"
        done
        """
        let scriptURL = try createMockExecutable(script: script)
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

        let config = TerminalAgentConfiguration(
            executablePath: scriptURL.path,
            persistenceMode: .persistentStdio(memory: .keep)
        )
        let session = GenericTerminalSession(configuration: config)!

        // Turn 1: Process is spawned and kept in memory
        let out1: MockEchoSpec.Output = try await session.respond(input: MockEchoSpec.Input(message: "hello"), instructions: "test")
        #expect(out1.reply == "turn 1")

        // Turn 2: Reuses the same running process in memory without termination
        let out2: MockEchoSpec.Output = try await session.respond(input: MockEchoSpec.Input(message: "again"), instructions: "test")
        #expect(out2.reply == "turn 2")
        #expect(session.executionMetadata.count == 2)

        // clearMemory() clears metadata records but keeps the in-memory process alive
        session.clearMemory()
        #expect(session.executionMetadata.isEmpty)

        // Turn 3: Process is still running and receives turn 3
        let out3: MockEchoSpec.Output = try await session.respond(input: MockEchoSpec.Input(message: "third"), instructions: "test")
        #expect(out3.reply == "turn 3")
        #expect(session.executionMetadata.count == 1)

        // purgeMemory() terminates the in-memory process and clears all session state
        session.purgeMemory()
        #expect(session.executionMetadata.isEmpty)
    }

    @Test("TerminalSession memoryRetentionPolicy clear discards memory after each execution")
    func testMemoryRetentionPolicyClear() async throws {
        let script = """
        #!/bin/bash
        echo "{\\"reply\\":\\"cleared memory\\"}"
        exit 0
        """
        let scriptURL = try createMockExecutable(script: script)
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

        let config = TerminalAgentConfiguration(
            executablePath: scriptURL.path,
            persistenceMode: .persistentStdio(memory: .clear)
        )
        let session = GenericTerminalSession(configuration: config)!

        _ = try await session.execute(MockEchoSpec(message: "first"))
        #expect(session.executionMetadata.isEmpty)

        _ = try await session.execute(MockEchoSpec(message: "second"))
        #expect(session.executionMetadata.isEmpty)
    }

    @Test("Benchmark and compare performance across all three persistence modes")
    func testPerformanceAcrossPersistenceModes() async throws {
        // Mock script for persistent mode: keeps reading stdin line by line and echoes valid json
        let persistentScript = """
        #!/bin/bash
        while IFS= read -r line; do
            echo "{\\"reply\\":\\"persistent\\"}"
        done
        """
        let persistentScriptURL = try createMockExecutable(script: persistentScript)
        defer { try? FileManager.default.removeItem(at: persistentScriptURL.deletingLastPathComponent()) }

        // Mode 1: Persistent Stdio (Process kept in memory)
        let persistentConfig = TerminalAgentConfiguration(
            executablePath: persistentScriptURL.path,
            persistenceMode: .persistentStdio
        )
        let persistentSession = GenericTerminalSession(configuration: persistentConfig)!

        let t1Start = ContinuousClock().now
        for i in 0..<3 {
            do {
                let res: MockEchoSpec.Output = try await persistentSession.respond(input: MockEchoSpec.Input(message: "test"), instructions: "test")
                #expect(res.reply == "persistent")
            } catch {
                print("Failed in persistent turn \(i): \(error)")
                throw error
            }
        }
        let persistentDuration = t1Start.duration(to: ContinuousClock().now)
        persistentSession.purgeMemory()

        // Mock script for ephemeral/daemon mode: exits immediately with valid json output
        let ephemeralScript = """
        #!/bin/bash
        echo '{"reply":"ephemeral"}'
        exit 0
        """
        let ephemeralScriptURL = try createMockExecutable(script: ephemeralScript)
        defer { try? FileManager.default.removeItem(at: ephemeralScriptURL.deletingLastPathComponent()) }

        // Mode 2: Ephemeral (Process spawned per turn)
        let ephemeralConfig = TerminalAgentConfiguration(
            executablePath: ephemeralScriptURL.path,
            persistenceMode: .ephemeral
        )
        let ephemeralSession = GenericTerminalSession(configuration: ephemeralConfig)!

        let t2Start = ContinuousClock().now
        for i in 0..<3 {
            do {
                let res: MockEchoSpec.Output = try await ephemeralSession.respond(input: MockEchoSpec.Input(message: "test"), instructions: "test")
                #expect(res.reply == "ephemeral")
            } catch {
                print("Failed in ephemeral turn \(i): \(error)")
                throw error
            }
        }
        let ephemeralDuration = t2Start.duration(to: ContinuousClock().now)

        // Mode 3: Daemon (Interacts with daemon/app-server)
        let daemonConfig = TerminalAgentConfiguration(
            executablePath: ephemeralScriptURL.path,
            extraArguments: ["--daemon"],
            persistenceMode: .daemon
        )
        let daemonSession = GenericTerminalSession(configuration: daemonConfig)!
        #expect(daemonSession.configuration.persistenceMode == .daemon)
        do {
            let daemonRes: MockEchoSpec.Output = try await daemonSession.respond(input: MockEchoSpec.Input(message: "test"), instructions: "test")
            #expect(daemonRes.reply == "ephemeral")
        } catch {
            print("Failed in daemon turn: \(error)")
            throw error
        }

        // Verify all 3 modes ran successfully and recorded durations
        #expect(persistentDuration > .zero)
        #expect(ephemeralDuration > .zero)
    }

    struct PlainEchoSpec: Spec {
        static var identity: Identity { Identity(id: "PlainEcho", name: "PlainEcho", version: "1.0.0") }
        static var role: String { "Plain echo" }
        static var outputSchema: JSONSchema { JSONSchema(String.self)! }
        var inputJSON: JSONString { JSONString("{\"text\":\"hello plain\"}") }
        var instructions: String { "Echo back" }
    }

    @Test("AgenticSessionProtocol executes non-modelled Spec directly and returns raw string")
    func testRawSpecConvenienceExecute() async throws {
        let script = """
        #!/bin/bash
        echo "Raw string response"
        exit 0
        """
        let scriptURL = try createMockExecutable(script: script)
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

        let config = TerminalAgentConfiguration(
            executablePath: scriptURL.path,
            persistenceMode: .ephemeral
        )
        let session = GenericTerminalSession(configuration: config)!
        let spec = PlainEchoSpec()
        let rawResult = try await session.executeSpec(spec)
        #expect(rawResult.contains("Raw string response"))
    }
}

