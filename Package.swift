// swift-tools-version:6.1

import PackageDescription

let package = Package(
    name: "gis-tools-gpx",
    platforms: [
        .iOS(.v15),
        .macOS(.v15),
        .tvOS(.v15),
        .watchOS(.v7),
    ],
    products: [
        .library(
            name: "GISToolsGPX",
            targets: ["GISToolsGPX"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Outdooractive/gis-tools", exact: "3.0.0-beta.6"),
    ],
    targets: [
        .target(
            name: "GISToolsGPX",
            dependencies: [
                .product(name: "GISTools", package: "gis-tools"),
            ]),
        .testTarget(
            name: "GISToolsGPXTests",
            dependencies: ["GISToolsGPX"],
            resources: [.copy("TestData")]),
    ]
)
