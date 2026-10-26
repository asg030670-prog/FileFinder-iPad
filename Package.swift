// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FileFinder",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "FileFinderCore", targets: ["FileFinderCore"]),
        .library(name: "FileFinderUI", targets: ["FileFinderUI"])
    ],
    targets: [
        // Platform-independent search engine, persistence and view models (Foundation only).
        .target(
            name: "FileFinderCore",
            path: "Sources/FileFinderCore"
        ),
        // SwiftUI user interface for iPad. Compiles to an empty module on non-iOS platforms.
        .target(
            name: "FileFinderUI",
            dependencies: ["FileFinderCore"],
            path: "Sources/FileFinderUI"
        ),
        .testTarget(
            name: "FileFinderCoreTests",
            dependencies: ["FileFinderCore"],
            path: "Tests/FileFinderCoreTests"
        )
    ]
)
