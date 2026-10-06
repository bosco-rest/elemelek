// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Elemelek",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Elemelek", targets: ["Elemelek"])],
    dependencies: [
        .package(url: "https://github.com/matrix-org/matrix-rust-components-swift", exact: "26.10.02"),
    ],
    targets: [
        // Pure logic with no UI and no SDK: parsing, highlighting, link finding, settings. Builds and tests anywhere.
        .target(name: "ElemelekCore"),
        .executableTarget(
            name: "Elemelek",
            dependencies: [
                "ElemelekCore",
                .product(name: "MatrixRustSDK", package: "matrix-rust-components-swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "ElemelekCoreTests", dependencies: ["ElemelekCore"]),
    ]
)
