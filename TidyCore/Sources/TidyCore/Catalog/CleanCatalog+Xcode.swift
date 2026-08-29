import Foundation

extension CleanCatalog {
    private struct T084DeviceResponse: Decodable {
        let devices: [String: [SimulatorDevice]]
    }

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
                dangerNote: "Wipes installed apps and data from every simulator device, including ones you're keeping",
                declaredRoot: { env in env.homeDirectory },
                locate: { _ in [] },
                action: .unavailable(reason: "Broad simulator erase-all is unavailable. Review individual devices when supported.")
            ),
            CleanItem(
                id: "deep.simulator.delete-approved",
                title: "Delete simulator devices you've approved for removal",
                tier: .deep,
                requires: .xcode,
                dangerNote: "Permanently deletes the device and everything installed on it",
                declaredRoot: { env in env.homeDirectory },
                locate: { _ in [] },
                action: .custom(.simulatorPrune)
            )
        ]

        return CleanCategory(
            id: "xcode-simulators",
            title: "Xcode & Simulators",
            items: derivedDataItems + simulatorCacheItems + deepItems
        )
    }

    static func discoverApprovedSimulators(environment: CleanEnvironment,
                                           orchestration: CoreOrchestrationContext) async
      -> ActionDiscovery {
        guard !environment.simulatorsApprovedForDeletion.isEmpty else {
            return ActionDiscovery(status: .noWork,
                reason: "No simulator is approved for removal.", targets: [])
        }
        guard environment.simulatorsApprovedForDeletion.count <= 256 else {
            return ActionDiscovery(status: .unavailable,
                reason: "The approved simulator inventory exceeds its bounded limit.", targets: [])
        }
        do {
            let devices = try await orchestration.withCommand {
                guard let path = await ToolLocator.locateAsync("xcrun") else {
                    throw CoreOrchestrationError.schedulerUnavailable
                }
                let output = try await ProcessRunner.runSimctlDevices(
                    xcrunURL: URL(fileURLWithPath: path))
                guard output.succeeded,
                      let data = output.standardOutput.data(using: .utf8) else {
                    throw CoreOrchestrationError.schedulerUnavailable
                }
                let response = try JSONDecoder().decode(T084DeviceResponse.self, from: data)
                guard response.devices.values.reduce(0, { $0 + $1.count }) <= 256 else {
                    throw CoreOrchestrationError.invalidPolicySnapshot
                }
                var flattened: [SimulatorDevice] = []
                for (runtime, members) in response.devices {
                    for var device in members {
                        device.runtimeIdentifier = runtime
                        flattened.append(device)
                    }
                }
                return flattened
            }
            let targets = SimulatorPruner.devicesEligibleForDeletion(allDevices: devices,
                approvedForDeletion: environment.simulatorsApprovedForDeletion).map {
                TargetPath(path: $0.udid, label: "\($0.name) [\($0.runtimeIdentifier)]",
                    isFilesystemPath: false)
            }
            return targets.isEmpty
                ? ActionDiscovery(status: .noWork,
                    reason: "No approved simulator is currently eligible.", targets: [])
                : ActionDiscovery(status: .available,
                    reason: "The bounded simulator inventory matched approved devices.",
                    targets: targets)
        } catch {
            return ActionDiscovery(status: .unavailable,
                reason: "The bounded simulator inventory was unavailable or invalid.", targets: [])
        }
    }
}
