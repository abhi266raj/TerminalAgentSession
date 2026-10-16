import Foundation
import Testing
import AgentAtomSource
@testable import TerminalAgentSessionSource

@Suite("Metadata flag regression tests")
struct MetadataFlagRegressionTests {
    @Test(arguments: [0, 1, 2, 3, 4, 7])
    func rawFlagsSelectModelAndDurationIndependently(mask: Int) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("metadata_flags_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("fixture.sh")
        try "#!/bin/sh\necho '{\"reply\":\"ok\"}'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let session = try #require(GenericTerminalSession(configuration: .init(
            executablePath: executable.path, model: "metadata-model",
            metadata: .init(rawValue: mask), persistenceMode: .daemon(memory: .keep))))
        _ = try await session.respond(
            to: "input", instructions: "instructions", schema: JSONString("{}"),
            for: ObjectIdentifier(Self.self)).get()
        let record = try #require(session.executionMetadata.first)
        #expect(record.modelIdentifier == ((mask & 1) != 0 ? "metadata-model" : nil))
        #expect((record.duration != nil) == ((mask & 2) != 0))
    }
}
