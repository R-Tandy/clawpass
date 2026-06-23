// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClawPass",
    platforms: [.iOS(.v16)],
    products: [
        .executable(name: "ClawPass", targets: ["ClawPass"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", .exact("0.14.1")),
    ],
    targets: [
        .executableTarget(
            name: "ClawPass",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: ".",
            exclude: ["Info.plist"],
            resources: [
                .process("Assets.xcassets")
            ]
        ),
    ]
)
