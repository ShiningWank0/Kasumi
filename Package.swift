// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kasumi",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Kasumi",
            targets: ["Kasumi"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Kasumi",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "KasumiTests",
            dependencies: ["Kasumi"],
            path: "Tests"
        )
    ]
)
