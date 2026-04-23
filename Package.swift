// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClipboardQueueMenuBar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "ClipboardQueueMenuBar",
            targets: ["ClipboardQueueMenuBar"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "ClipboardQueueMenuBar",
            path: "Sources/ClipboardQueueMenuBar"
        ),
    ]
)
