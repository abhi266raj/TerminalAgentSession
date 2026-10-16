import Foundation
import Testing
import AgentAtom
@testable import TerminalAgentSession

@Suite("Antigravity regression tests")
struct AntigravityRegressionTests {
    private func executeFixture(_ event: String) async throws -> Result<String, AgenticError> {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("agy_contract_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("agy.sh")
        let script = """
        #!/bin/bash
        print_count=0
        prompt=''
        while [[ "$#" -gt 0 ]]; do
            case "$1" in
                --print=*) prompt="${1#--print=}"; print_count=$((print_count + 1)) ;;
                --print) echo 'Print must bind its prompt' >&2; exit 2 ;;
                --json-schema) [[ -f "$2" ]] || exit 3; shift ;;
            esac
            shift
        done
        [[ "$print_count" == "1" ]] || exit 4
        printf '%s' "$prompt" > prompt.txt
        echo '{"event":"init"}'
        echo '\(event)'
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let session = try #require(AntigravityTerminalSession(configuration: .init(
            executablePath: executable.path, model: "fixture-model", workingDirectory: root,
            extraArguments: ["--effort", "low"])))
        #expect(session.configuration.persistenceMode == .ephemeral)
        let input = "Input with spaces, 'quotes', --flags\nand a second line"
        let instructions = "System instructions"
        let result = await session.respond(
            to: input, instructions: instructions, schema: JSONString("{\"type\":\"object\"}"),
            for: ObjectIdentifier(Self.self))
        let actualPrompt = try String(contentsOf: root.appendingPathComponent("prompt.txt"), encoding: .utf8)
        #expect(actualPrompt == "\(instructions)\n\nInput:\n\(input)")
        return result
    }

    @Test(arguments: [false, true])
    func successPreservesStructuredResult(native: Bool) async throws {
        let event = native
            ? #"{"event":"result","result":{"status":"SUCCESS","structured_output":{"reply":"ok"}}}"#
            : #"{"type":"result","response":"{\"reply\":\"ok\"}"}"#
        let output = try await executeFixture(event).get()
        let decoded = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: String]
        #expect(decoded?["reply"] == "ok")
    }

    @Test(arguments: ["FAILED", "failed", "ERROR", "CANCELLED"])
    func failedStatusCannotReturnStructuredPayload(status: String) async throws {
        let event = """
        {"event":"result","result":{"status":"\(status)","response":"Done","structured_output":{"reply":"private-result"}}}
        """
        switch try await executeFixture(event) {
        case .success: Issue.record("Failed native status was returned as success.")
        case .failure(let error):
            #expect(error.localizedDescription.contains("unsuccessful result"))
            #expect(!error.localizedDescription.contains("private-result"))
        }
    }

    @Test(arguments: [false, true])
    func explicitErrorFlagCannotReturnPayload(native: Bool) async throws {
        let event = native
            ? #"{"event":"result","result":{"status":"SUCCESS","is_error":true,"structured_output":{"reply":"private-result"}}}"#
            : #"{"type":"result","is_error":true,"response":"{\"reply\":\"private-result\"}"}"#
        switch try await executeFixture(event) {
        case .success: Issue.record("Error result was returned as success.")
        case .failure(let error): #expect(!error.localizedDescription.contains("private-result"))
        }
    }
}
