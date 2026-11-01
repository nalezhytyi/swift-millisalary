// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MillisalaryCore",
    // The texts the core makes (the menu bar's rows, the notifications) are
    // English in the source and translated in Localizable.xcstrings
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MillisalaryCore", targets: ["MillisalaryCore"]),
    ],
    targets: [
        .target(
            name: "MillisalaryCore",
            resources: [.process("Localizable.xcstrings")]
        ),
        .testTarget(
            name: "MillisalaryCoreTests",
            dependencies: ["MillisalaryCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
