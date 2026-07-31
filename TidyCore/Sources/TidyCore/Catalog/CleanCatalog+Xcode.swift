extension CleanCatalog {
    /// Section 3 of the shell script (safe tier) plus `simctl delete
    /// unavailable` and the CodingAssistant index. Simulator device
    /// deletion against the user's keep-list, and Archives, are Deep tier.
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

        let deepItems = [
            fixedPathItem(
                id: "deep.xcode.archives",
                title: "Xcode Archives",
                tier: .deep,
                requires: .xcode,
                dangerNote: "Deletes the dSYMs needed to symbolicate crash reports from builds you've already shipped",
                relativePath: "Library/Developer/Xcode/Archives",
                declaredRootRelativePath: "Library/Developer/Xcode",
                action: .deleteContents
            ),
            CleanItem(
                id: "deep.simulator.erase-all",
                title: "Erase all simulator app data and settings",
                tier: .deep,
                requires: .xcode,
                dangerNote: "Wipes installed apps and data from every simulator device, including ones you're keeping",
                declaredRoot: { env in env.homeDirectory },
                locate: { _ in [] },
                action: .runTool(ToolCommand(.xcrun, ["simctl", "erase", "all"]))
            ),
            CleanItem(
                id: "deep.simulator.delete-approved",
                title: "Delete simulator devices you've approved for removal",
                tier: .deep,
                requires: .xcode,
                dangerNote: "Permanently deletes the device and everything installed on it",
                declaredRoot: { env in env.homeDirectory },
                locate: { env in
                    guard !env.simulatorsApprovedForDeletion.isEmpty else { return [] }
                    let devices = SimctlClient.listDevicesSync()
                    return SimulatorPruner.devicesEligibleForDeletion(
                        allDevices: devices,
                        approvedForDeletion: env.simulatorsApprovedForDeletion
                    ).map { device in
                        TargetPath(path: device.udid, label: "\(device.name) [\(device.runtimeIdentifier)]", isFilesystemPath: false)
                    }
                },
                action: .custom(.simulatorPrune)
            )
        ]

        return CleanCategory(
            id: "xcode-simulators",
            title: "Xcode & Simulators",
            items: derivedDataItems + simulatorCacheItems + deepItems
        )
    }
}
