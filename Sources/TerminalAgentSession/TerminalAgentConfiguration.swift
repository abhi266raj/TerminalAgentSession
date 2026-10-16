import Foundation
import AgentAtom

/// Common configuration shared across all terminal CLI agent sessions.
public struct TerminalAgentConfiguration: Sendable, Equatable {
    /// Strategy for process lifecycle across session turns.
    public enum ProcessPersistenceMode: Sendable, Equatable {
        /// Policy for session memory retention across turns.
        public enum MemoryRetentionPolicy: Sendable, Equatable {
            /// Keeps session memory and execution context intact across turns.
            case keep
            /// Automatically clears session memory and execution history after each turn.
            case clear
        }

        /// Keeps a long-running subprocess active in memory and streams input/output over persistent stdin/stdout.
        case persistentStdio(memory: MemoryRetentionPolicy = .clear)
        /// Interacts with an existing agent daemon or background server (e.g. app-server / remote-control).
        case daemon(memory: MemoryRetentionPolicy = .clear)
        /// Spawns a dedicated process per execution with pre-warmed path resolution and configuration.
        case ephemeral

        /// Default persistent stdio configuration.
        public static let persistentStdio: ProcessPersistenceMode = .persistentStdio(memory: .clear)
        /// Default daemon configuration.
        public static let daemon: ProcessPersistenceMode = .daemon(memory: .clear)

        /// The configured memory retention policy, or `.clear` if ephemeral.
        public var memoryRetentionPolicy: MemoryRetentionPolicy {
            switch self {
            case .persistentStdio(let memory):
                return memory
            case .daemon(let memory):
                return memory
            case .ephemeral:
                return .clear
            }
        }
    }

    /// Alias for backwards compatibility and ease of access.
    public typealias MemoryRetentionPolicy = ProcessPersistenceMode.MemoryRetentionPolicy

    /// The executable name or absolute file path to the CLI binary.
    public var executablePath: String
    /// Optional model identifier override (e.g. `gpt-4o`, `gemini-1.5-pro`, `grok-beta`).
    public var model: String?
    /// Working directory for subprocess execution.
    public var workingDirectory: URL?
    /// Additional CLI arguments passed directly to the tool.
    public var extraArguments: CLIArguments
    /// Custom search paths to prepend when resolving the CLI binary.
    public var additionalSearchPaths: [String]
    /// Metadata tracking preferences.
    public var metadata: AgenticExecutionMetadata.Fields
    /// Optional conversation identifier to resume/maintain context across executions.
    public var conversationID: String?
    /// Mode of process lifecycle management across turns. Defaults to `.persistentStdio()`.
    public var persistenceMode: ProcessPersistenceMode
    /// Policy for retaining or clearing session memory, derived from `persistenceMode`.
    public var memoryRetentionPolicy: MemoryRetentionPolicy {
        persistenceMode.memoryRetentionPolicy
    }
    /// Pre-resolved URL of the binary, computed on initialization.
    var resolvedURL: URL?

    public init(
        executablePath: String,
        model: String? = nil,
        workingDirectory: URL? = nil,
        extraArguments: CLIArguments = [],
        additionalSearchPaths: [String] = [],
        metadata: AgenticExecutionMetadata.Fields = [],
        conversationID: String? = nil,
        persistenceMode: ProcessPersistenceMode = .persistentStdio
    ) {
        self.executablePath = executablePath
        self.model = model
        self.workingDirectory = workingDirectory
        self.extraArguments = extraArguments
        self.additionalSearchPaths = additionalSearchPaths
        self.metadata = metadata
        self.conversationID = conversationID
        self.persistenceMode = persistenceMode
        self.resolvedURL = nil
    }

    public init(
        executablePath: String,
        model: String? = nil,
        workingDirectory: URL? = nil,
        extraArguments: [String],
        additionalSearchPaths: [String] = [],
        metadata: AgenticExecutionMetadata.Fields = [],
        conversationID: String? = nil,
        persistenceMode: ProcessPersistenceMode = .persistentStdio
    ) {
        self.init(
            executablePath: executablePath,
            model: model,
            workingDirectory: workingDirectory,
            extraArguments: CLIArguments(extraArguments),
            additionalSearchPaths: additionalSearchPaths,
            metadata: metadata,
            conversationID: conversationID,
            persistenceMode: persistenceMode
        )
    }
}
