// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ClawPass",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "ClawPass", targets: ["ClawPass"])
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.14.0")
    ],
    targets: [
        .target(
            name: "ClawPass",
            dependencies: ["SQLite"],
            path: "ClawPass/ios/ClawPass"
        )
    ]
)
