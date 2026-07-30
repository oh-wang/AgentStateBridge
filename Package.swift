// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AgentStateBridge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AgentStateCore", targets: ["AgentStateCore"]),
        .library(name: "MacSignalSources", targets: ["MacSignalSources"]),
        .library(name: "AgentStateBridgeService", targets: ["AgentStateBridgeService"]),
        .library(name: "AgentStateRuntime", targets: ["AgentStateRuntime"]),
        .executable(name: "AgentStateInspector", targets: ["AgentStateInspector"]),
        .executable(
            name: "AgentStateExampleConsumer",
            targets: ["AgentStateExampleConsumer"]
        )
    ],
    targets: [
        .target(name: "AgentStateCore"),
        .target(
            name: "MacSignalSources",
            dependencies: ["AgentStateCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .target(
            name: "AgentStateBridgeService",
            dependencies: ["AgentStateCore"]
        ),
        .target(
            name: "AgentStateRuntime",
            dependencies: [
                "AgentStateCore",
                "MacSignalSources",
                "AgentStateBridgeService"
            ],
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "AgentStateInspector",
            dependencies: [
                "AgentStateCore",
                "MacSignalSources",
                "AgentStateRuntime"
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "AgentStateExampleConsumer",
            dependencies: ["AgentStateCore", "AgentStateBridgeService"]
        ),
        .testTarget(
            name: "AgentStateCoreTests",
            dependencies: ["AgentStateCore"]
        ),
        .testTarget(
            name: "AgentStateBridgeServiceTests",
            dependencies: ["AgentStateCore", "AgentStateBridgeService"]
        ),
        .testTarget(
            name: "AgentStateRuntimeTests",
            dependencies: ["AgentStateCore", "AgentStateRuntime"]
        )
    ]
)
