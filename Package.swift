// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Caffeinator",
    platforms: [.macOS(.v11)],
    targets: [
        .executableTarget(
            name: "Caffeinator",
            path: "Sources/Caffeinator"
        ),
        .testTarget(
            name: "CaffeinatorTests",
            dependencies: ["Caffeinator"],
            path: "Tests/CaffeinatorTests"
        ),
    ]
)
