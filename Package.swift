// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "ixy",
	platforms: [
		.macOS(.v11),
	],
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
			dependencies: [.target(name: "CVirtio")]),
		.target(
			name: "CVirtio",
			dependencies: []),
        .executableTarget(
            name: "app",
            dependencies: [.target(name: "ixy")]),
    ]
)
