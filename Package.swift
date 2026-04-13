// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LogViewer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "LogViewer",
            targets: ["LogViewer"]
        )
    ],
    targets: [
        .executableTarget(
            name: "LogViewer",
            path: "Sources"
        ),
        .testTarget(
            name: "LogViewerTests",
            dependencies: ["LogViewer"],
            path: "Tests"
        ),
        // UI Tests target (requires Xcode to run)
        // To run: open Package.swift in Xcode, then Cmd+U
        .testTarget(
            name: "LogViewerUITests",
            dependencies: [],
            path: "UITests"
        )
    ]
)
