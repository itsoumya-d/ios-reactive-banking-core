// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BankingCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "BankingCore",
            targets: ["BankingCore"]
        ),
    ],
    targets: [
        .target(
            name: "BankingCore",
            path: "Sources/BankingCore"
        ),
        .testTarget(
            name: "BankingCoreTests",
            dependencies: ["BankingCore"],
            path: "Tests/BankingCoreTests"
        ),
    ]
)
