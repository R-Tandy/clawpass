// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClawPass",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "ClawPass",
            targets: ["ClawPass"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
    ],
    targets: [
        .target(
            name: "ClawPass",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: "ClawPass",
            exclude: ["Info.plist"]
        ),
    ]
)
