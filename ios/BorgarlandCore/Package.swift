// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BorgarlandCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    products: [
        .library(name: "BorgarlandCore", targets: ["BorgarlandCore"]),
    ],
    targets: [
        .target(name: "BorgarlandCore"),
        .testTarget(
            name: "BorgarlandCoreTests",
            dependencies: ["BorgarlandCore"]
        ),
    ]
)
