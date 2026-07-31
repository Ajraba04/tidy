extension CleanCatalog {
    /// Section 3 of the shell script (safe tier) plus `simctl delete
    /// unavailable` and the CodingAssistant index. Simulator device
    /// deletion against the user's keep-list, and Archives, are Deep-tier
    /// (Phase 6).
    static var xcodeAndSimulators: CleanCategory {
        let derivedDataItems = [
            fixedPathItem(
                id: "safe.xcode.derived-data",
                title: "Xcode DerivedData",
                tier: .safe,
                requires: .xcode,
                dangerNote: "Next build recompiles everything",
                relativePath: "Library/Developer/Xcode/DerivedData",
                declaredRootRelativePath: "Library/Developer/Xcode",
                action: .deleteContents
            ),
            fixedPathItem(
                id: "safe.xcode.documentation-cache",
                title: "Xcode DocumentationCache",
                tier: .safe,
                requires: .xcode,
                relativePath: "Library/Developer/Xcode/DocumentationCache",
                declaredRootRelativePath: "Library/Developer/Xcode",
                action: .deleteContents
            ),
            fixedPathItem(
                id: "safe.xcode.ios-device-support",
                title: "Xcode iOS DeviceSupport",
                tier: .safe,
                requires: .xcode,
                costNote: "Xcode re-downloads device support files when a matching device connects",
                relativePath: "Library/Developer/Xcode/iOS DeviceSupport",
                declaredRootRelativePath: "Library/Developer/Xcode",
                action: .deleteContents
            ),
            fixedPathItem(
                id: "safe.xcode.watchos-device-support",
                title: "Xcode watchOS DeviceSupport",
                tier: .safe,
                requires: .xcode,
                costNote: "Xcode re-downloads device support files when a matching device connects",
                relativePath: "Library/Developer/Xcode/watchOS DeviceSupport",
                declaredRootRelativePath: "Library/Developer/Xcode",
                action: .deleteContents
            ),
            fixedPathItem(
                id: "safe.xcode.products",
                title: "Xcode Products",
                tier: .safe,
                requires: .xcode,
                relativePath: "Library/Developer/Xcode/Products",
                declaredRootRelativePath: "Library/Developer/Xcode",
                action: .deleteContents
            ),
            fixedPathItem(
                id: "safe.xcode.coding-assistant",
                title: "Xcode CodingAssistant index",
                tier: .safe,
                requires: .xcode,
                relativePath: "Library/Developer/Xcode/CodingAssistant",
                declaredRootRelativePath: "Library/Developer/Xcode",
                action: .deleteContents
            )
        ]

        let simulatorCacheItems = [
            fixedPathItem(
                id: "safe.simulator.core-simulator-caches",
                title: "CoreSimulator/Caches",
                tier: .safe,
                requires: .xcode,
                relativePath: "Library/Developer/CoreSimulator/Caches",
                declaredRootRelativePath: "Library/Developer/CoreSimulator",
                action: .deleteContents
            ),
            fixedPathItem(
                id: "safe.simulator.core-simulator-temp",
                title: "CoreSimulator/Temp",
                tier: .safe,
                requires: .xcode,
                relativePath: "Library/Developer/CoreSimulator/Temp",
                declaredRootRelativePath: "Library/Developer/CoreSimulator",
                action: .deleteContents
            ),
            fixedPathItem(
                id: "safe.simulator.playground-devices",
                title: "Playground devices (XCPGDevices)",
                tier: .safe,
                requires: .xcode,
                relativePath: "Library/Developer/XCPGDevices",
                declaredRootRelativePath: "Library/Developer",
                action: .deleteContents
            ),
            fixedPathItem(
                id: "safe.simulator.xctest-devices",
                title: "XCTest devices",
                tier: .safe,
                requires: .xcode,
                relativePath: "Library/Developer/XCTestDevices",
                declaredRootRelativePath: "Library/Developer",
                action: .deleteContents
            ),
            CleanItem(
                id: "safe.simulator.delete-unavailable",
                title: "Delete unavailable simulator devices",
                tier: .safe,
                requires: .xcode,
                declaredRoot: { env in env.homeDirectory },
                locate: { _ in [] },
                action: .runTool(ToolCommand(.xcrun, ["simctl", "delete", "unavailable"]))
            )
        ]

        return CleanCategory(
            id: "xcode-simulators",
            title: "Xcode & Simulators",
            items: derivedDataItems + simulatorCacheItems
        )
    }
}
