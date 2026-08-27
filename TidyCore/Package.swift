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
            name: "TidyCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "TidyCoreTests",
            dependencies: ["TidyCore"],
            exclude: ["Fixtures/T04ProcessFixture.c", "Fixtures/T05SettingsProcessDriver.swift"],
            resources: [.copy("Fixtures/Config")]
        )
    ]
)
