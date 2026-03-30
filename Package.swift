// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ShaaaareMyScreeeen",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4"),
    ],
    targets: [
        .executableTarget(
            name: "ShaaaareMyScreeeen",
            dependencies: ["Sparkle"],
            path: "Sources/App",
            resources: [.process("../../Resources")]
        ),
        .executableTarget(
            name: "shaaaare-mcp",
            path: "Sources/MCP"
        )
    ]
)
