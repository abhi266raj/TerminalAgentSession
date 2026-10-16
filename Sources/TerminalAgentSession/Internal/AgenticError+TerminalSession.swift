import Foundation
import AgentAtom

// MARK: - AgenticError Extension

extension AgenticError {
    /// Constructs an `AgenticError` from any underlying Error or failure.
    /// If the error is already `AgenticError`, returns it directly; otherwise wraps it as `.operationFailed`.
    init(_ error: Error) {
        if let agentic = error as? AgenticError {
            self = agentic
        } else {
            self = .operationFailed(reason: error.localizedDescription)
        }
    }

    /// Constructs an `AgenticError.operationFailed` with an action description and underlying error.
    init(action: String, error: Error) {
        self = .operationFailed(reason: "\(action): \(error.localizedDescription)")
    }

    /// Constructs an `AgenticError.operationFailed` when a subprocess terminates with a non-zero exit code.
    init(executablePath: String, exitCode: Int32, stderr: String) {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        self = .operationFailed(reason: "\(executablePath) exited with code \(exitCode): \(trimmed)")
    }
}
