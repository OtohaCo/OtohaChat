// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OtohaChatKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "OtohaChatKit", targets: ["OtohaChatKit"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/OtohaCo/SwiftAgent.git",
            exact: "1.0.0-rc.3"
        ),
    ],
    targets: [
        .target(
            name: "OtohaChatKit",
            dependencies: [
                .product(name: "AgentCore", package: "SwiftAgent"),
                .product(name: "AgentModels", package: "SwiftAgent"),
                .product(name: "AgentProviders", package: "SwiftAgent"),
                .product(name: "AgentAppleProvider", package: "SwiftAgent"),
                .product(name: "AgentTools", package: "SwiftAgent"),
                .product(name: "AgentUsage", package: "SwiftAgent"),
                .product(name: "AgentCatalog", package: "SwiftAgent"),
            ],
            path: "Sources/OtohaChatKit",
            exclude: ["README.md"],
            swiftSettings: [
                // App-target SWIFT_ACTIVE_COMPILATION_CONDITIONS do not reach this
                // package. Release archives (TestFlight) must compile the kit with
                // the same PCC request the signed entitlements file declares.
                .define("OTOHACHAT_PCC", .when(configuration: .release)),
            ]
        ),
        .testTarget(
            name: "OtohaChatKitTests",
            dependencies: [
                "OtohaChatKit",
                .product(name: "AgentCore", package: "SwiftAgent"),
                .product(name: "AgentModels", package: "SwiftAgent"),
                .product(name: "AgentProviders", package: "SwiftAgent"),
                .product(name: "AgentTools", package: "SwiftAgent"),
                .product(name: "AgentUsage", package: "SwiftAgent"),
                .product(name: "AgentCatalog", package: "SwiftAgent"),
            ],
            path: "Tests/OtohaChatKitTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
