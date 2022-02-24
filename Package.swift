// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "ixy",
    products: [
        .library(
            name: "ixy",
            targets: ["ixy"]),
        .executable(
            name: "app",
            targets: ["app"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "ixy",
            dependencies: []),
        .executableTarget(
            name: "app",
            dependencies: [.target(name: "ixy")]),
    ]
)
