// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ShaaaareMyScreeeen",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ShaaaareMyScreeeen",
            path: "Sources/App",
            resources: [.process("../../Resources")]
        )
    ]
)
