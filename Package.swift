// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "asc-mcp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "asc-mcp", targets: ["asc-mcp"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.0")
    ],
    targets: [
        .executableTarget(
            name: "asc-mcp",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "ASCMCPTests",
            dependencies: [
                "asc-mcp",
                .product(name: "MCP", package: "swift-sdk")
            ],
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
