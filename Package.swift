// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Tama",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Tama",
            targets: ["Droppy"]
        ),
        // Loaded by /usr/bin/perl, not linked into Tama: see MediaRemoteAdapterProcess.
        .library(
            name: "TamaMediaRemoteAdapter",
            type: .dynamic,
            targets: ["DroppyMediaRemoteAdapter"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Droppy",
            path: "Sources"
        ),
        .target(
            name: "DroppyMediaRemoteAdapter",
            path: "Adapters/MediaRemoteAdapter",
            linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("AppKit")]
        ),
        .testTarget(
            name: "DroppyTests",
            dependencies: ["Droppy"],
            path: "Tests/DroppyTests"
        )
    ]
)
