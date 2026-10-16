import Foundation

/// A type-safe representation of command-line arguments.
///
/// Encapsulates arguments as strongly-typed options, flags, and values rather than raw `[String]`,
/// providing validation, safe shell-escaping awareness, and clean fluent building.
public struct CLIArguments: Sendable, Equatable, ExpressibleByArrayLiteral {
    /// Internal storage of argument tokens.
    public private(set) var rawTokens: [String]

    /// Initializes with empty arguments.
    public init() {
        self.rawTokens = []
    }

    /// Initializes with raw string arguments.
    public init(_ tokens: [String]) {
        self.rawTokens = tokens
    }

    /// ExpressibleByArrayLiteral support.
    public init(arrayLiteral elements: String...) {
        self.rawTokens = elements
    }

    /// Appends a raw flag or option (e.g. `"--json"`).
    public mutating func append(_ token: String) {
        rawTokens.append(token)
    }

    /// Appends an option with a corresponding value (e.g. `"--model" "gpt-4"`).
    public mutating func append(option: String, value: String) {
        rawTokens.append(option)
        rawTokens.append(value)
    }

    /// Appends an option with a corresponding value only if the value is non-nil and non-empty.
    public mutating func append(option: String, optionalValue: String?) {
        guard let optionalValue, !optionalValue.isEmpty else { return }
        rawTokens.append(option)
        rawTokens.append(optionalValue)
    }

    /// Appends a boolean flag if true (e.g. `"--dangerously-skip-permissions"`).
    public mutating func append(flag: String, condition: Bool = true) {
        if condition {
            rawTokens.append(flag)
        }
    }

    /// Concatenates two `CLIArguments`.
    public static func + (lhs: CLIArguments, rhs: CLIArguments) -> CLIArguments {
        CLIArguments(lhs.rawTokens + rhs.rawTokens)
    }

    /// Appends another `CLIArguments` in place.
    public static func += (lhs: inout CLIArguments, rhs: CLIArguments) {
        lhs.rawTokens.append(contentsOf: rhs.rawTokens)
    }

    /// Appends an array of tokens in place.
    public static func += (lhs: inout CLIArguments, rhs: [String]) {
        lhs.rawTokens.append(contentsOf: rhs)
    }

    /// Appends a single token in place.
    public static func += (lhs: inout CLIArguments, rhs: String) {
        lhs.rawTokens.append(rhs)
    }

    /// Returns the last token, if any.
    public var last: String? {
        rawTokens.last
    }

    /// Returns whether arguments are empty.
    public var isEmpty: Bool {
        rawTokens.isEmpty
    }

    /// Number of argument tokens.
    public var count: Int {
        rawTokens.count
    }
}
