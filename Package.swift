// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Quota",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Quota", targets: ["Quota"])
    ],
    targets: [
        .executableTarget(
            name: "Quota",
            path: "Sources/Quota",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
