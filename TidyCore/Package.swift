// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TidyCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TidyCore", targets: ["TidyCore"])
    ],
    targets: [
        .target(
            name: "TidyCore"
        ),
        .testTarget(
            name: "TidyCoreTests",
            dependencies: ["TidyCore"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
