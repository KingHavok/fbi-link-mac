// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FBILinkMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FBILinkMac",
            path: "Sources/FBILinkMac",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "ARPDebug",
            path: "Sources/ARPDebug"
        ),
    ]
)
