// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TerminalAgentSession",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TerminalAgentSession", targets: ["TerminalAgentSession"]),
        .library(name: "TerminalAgentSessionSource", targets: ["TerminalAgentSessionSource"])
    ],
    dependencies: [
        .package(url: "https://github.com/abhi266raj/AgentAtom", exact: "0.1.0")
    ],
    targets: [
        .target(
            name: "TerminalAgentSession",
            dependencies: [
                .product(name: "AgentAtom", package: "AgentAtom")
            ],
            path: "Sources/TerminalAgentSession"
        ),
        .target(
            name: "TerminalAgentSessionSource",
            dependencies: [
                .product(name: "AgentAtomSource", package: "AgentAtom")
            ],
            path: "Sources/TerminalAgentSessionSource"
        ),
        .testTarget(
            name: "TerminalAgentSessionTests",
            dependencies: ["TerminalAgentSession"]
        ),
        .testTarget(
            name: "TerminalAgentSessionSourceTests",
            dependencies: ["TerminalAgentSessionSource"]
        )
    ],
    swiftLanguageModes: [.v6]
)
