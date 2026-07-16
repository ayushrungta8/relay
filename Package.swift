// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Relay",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "RelayApp", targets: ["RelayApp"]),
        .library(name: "RelayCore", targets: ["RelayCore"]),
        .library(name: "RelayBrain", targets: ["RelayBrain"]),
        .library(name: "RelayCodexClient", targets: ["RelayCodexClient"]),
        .library(name: "RelayCodexBridge", targets: ["RelayCodexBridge"]),
        .library(name: "RelayVoice", targets: ["RelayVoice"]),
    ],
    targets: [
        .target(name: "RelayCore"),
        .target(name: "RelayBrain"),
        .target(
            name: "RelayCodexClient",
            dependencies: ["RelayCore"]
        ),
        .target(
            name: "RelayCodexBridge",
            dependencies: [
                "RelayBrain",
                "RelayCodexClient",
                "RelayCore",
                "RelayVoice",
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
            ]
        ),
        .target(
            name: "RelayVoice",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "RelayApp",
            dependencies: [
                "RelayBrain",
                "RelayCodexBridge",
                "RelayCodexClient",
                "RelayCore",
                "RelayVoice",
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .testTarget(
            name: "RelayCoreTests",
            dependencies: ["RelayCore"]
        ),
        .testTarget(
            name: "RelayCodexClientTests",
            dependencies: ["RelayCore", "RelayCodexClient"]
        ),
        .testTarget(
            name: "RelayCodexBridgeTests",
            dependencies: [
                "RelayBrain",
                "RelayCodexBridge",
                "RelayCodexClient",
                "RelayCore",
                "RelayVoice",
            ]
        ),
        .testTarget(
            name: "RelayBrainTests",
            dependencies: ["RelayBrain"]
        ),
        .testTarget(
            name: "RelayVoiceTests",
            dependencies: ["RelayVoice"]
        ),
        .testTarget(
            name: "RelayAppTests",
            dependencies: [
                "RelayApp",
                "RelayBrain",
                "RelayCodexBridge",
                "RelayCodexClient",
                "RelayCore",
                "RelayVoice",
            ]
        ),
    ]
)
