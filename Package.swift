// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LookinMCP",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "lookin-mcp",
            targets: ["LookinMCPServer"]
        )
    ],
    targets: [
        .target(
            name: "LookinBridgeBase",
            path: "LookinServer/Src/Base",
            publicHeadersPath: ".",
            cSettings: [
                .define("SHOULD_COMPILE_LOOKIN_SERVER", to: "1"),
                .unsafeFlags(["-fobjc-arc"])
            ]
        ),
        .target(
            name: "LookinBridgeShared",
            dependencies: ["LookinBridgeBase"],
            path: "LookinServer/Src/Main/Shared",
            exclude: [
                "LookinAppInfo.m"
            ],
            publicHeadersPath: ".",
            cSettings: [
                .define("SHOULD_COMPILE_LOOKIN_SERVER", to: "1"),
                .headerSearchPath("."),
                .headerSearchPath("Category"),
                .headerSearchPath("Peertalk"),
                .unsafeFlags(["-fobjc-arc"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security")
            ]
        ),
        .target(
            name: "LookinBridgeCore",
            dependencies: ["LookinBridgeShared"],
            path: "Sources/LookinBridgeCore",
            publicHeadersPath: "include",
            cSettings: [
                .define("SHOULD_COMPILE_LOOKIN_SERVER", to: "1"),
                .headerSearchPath("include"),
                .unsafeFlags(["-fobjc-arc"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "LookinMCPServer",
            dependencies: ["LookinBridgeCore"],
            path: "Sources/LookinMCPServer"
        ),
        .testTarget(
            name: "LookinMCPServerTests",
            dependencies: ["LookinMCPServer"],
            path: "Tests/LookinMCPServerTests"
        )
    ]
)
