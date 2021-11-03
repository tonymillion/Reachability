// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "Reachability",
    platforms: [
        .iOS(.v9),
        .macOS(.v10_10),
        .tvOS(.v9),
    ],
    products: [
        .library(
            name: "Reachability",
            targets: ["Reachability"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Reachability"),
    ]
)
