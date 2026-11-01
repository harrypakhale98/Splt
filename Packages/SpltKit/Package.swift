// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SpltKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SpltCore", targets: ["SpltCore"])
    ],
    targets: [
        .target(name: "SpltCore"),
        .testTarget(name: "SpltCoreTests", dependencies: ["SpltCore"])
    ]
)
