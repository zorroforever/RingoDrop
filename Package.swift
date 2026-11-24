// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RingoDrop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "RingoDrop", targets: ["RingoDrop"])
    ],
    targets: [
        .executableTarget(
            name: "RingoDrop",
            path: "Sources/RingoDrop"
        )
    ]
)
