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
            path: "Tests",
            exclude: [
                "manual_filewatcher_test.swift",
                "manual_refresh_test.swift",
                "validate_parser.swift",
                "integration_test.swift",
                "integration_openfile_test.swift",
                "SyntaxHighlighterManualTest.swift",
                "generate_test_logs.sh",
                "README.md",
            ]
        ),
        // UI Tests target - XCUITest CANNOT run via `swift test`
        // XCUITest requires a UI test bundle which only Xcode can configure.
        // To run E2E tests: ./build_app.sh && ./test_e2e.sh
        // Or open Package.swift in Xcode and Cmd+U
        // .testTarget(
        //     name: "LogViewerUITests",
        //     dependencies: ["LogViewer"],
        //     path: "UITests"
        // )
    ]
)
