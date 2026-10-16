import Foundation
import Testing
@testable import TerminalAgentSessionSource
import AgentAtomSource

@Suite("TerminalAgentSessionSource Tests")
struct TerminalAgentSessionSourceTests {
    @Test func testSourceTargetInstantiatesAndExecutes() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("tas_source_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let mockScript = tempDir.appendingPathComponent("mock.sh")
        let script = """
        #!/bin/bash
        echo "Source target test line"
        exit 0
        """
        try script.write(to: mockScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockScript.path)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        guard let session = GenericTerminalSession(executablePath: mockScript.path) else {
            Issue.record("Failed to initialize GenericTerminalSession from source")
            return
        }

        struct SimpleSpec: Spec {
            static var identity: Identity { Identity(id: "simple_spec", name: "SimpleSpec", version: "1.0.0") }
            static var outputSchema: JSONSchema { JSONSchema(String.self)! }
            static var role: String { "tester" }
            var inputJSON: JSONString { JSONString("{\"test\":true}") }
            var instructions: String { "Run test" }
        }

        let result = await session.respond(to: "test", instructions: "run", schema: JSONString("{}"), for: ObjectIdentifier(SimpleSpec.self))
        switch result {
        case .success(let text):
            #expect(text.contains("Source target test line"))
        case .failure(let error):
            Issue.record("Unexpected error: \(error)")
        }
    }
}
