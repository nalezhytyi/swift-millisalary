// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MillisalaryCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MillisalaryCore", targets: ["MillisalaryCore"]),
    ],
    targets: [
        .target(name: "MillisalaryCore"),
        .testTarget(
            name: "MillisalaryCoreTests",
            dependencies: ["MillisalaryCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
