// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "SwitchGPT",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(
      name: "SwitchGPTSafetyCore",
      targets: ["SwitchGPTSafetyCore"]
    ),
    .library(
      name: "SwitchGPTServiceManagementStatus",
      targets: ["SwitchGPTServiceManagementStatus"]
    ),
    .library(
      name: "SwitchGPTAppCore",
      targets: ["SwitchGPTAppCore"]
    ),
    .library(
      name: "SwitchGPTDesktopIntegration",
      targets: ["SwitchGPTDesktopIntegration"]
    ),
    .executable(
      name: "SwitchGPTApp",
      targets: ["SwitchGPTApp"]
    ),
    .executable(
      name: "SwitchGPTSafetySimulator",
      targets: ["SwitchGPTSafetySimulator"]
    ),
    .executable(
      name: "SwitchGPTBootRecovery",
      targets: ["SwitchGPTBootRecovery"]
    ),
    .executable(
      name: "SwitchGPTRecoverySupervisor",
      targets: ["SwitchGPTRecoverySupervisor"]
    ),
    .executable(
      name: "SwitchGPTLifecycleHost",
      targets: ["SwitchGPTLifecycleHost"]
    ),
    .executable(
      name: "SwitchGPTLifecycleActivationHost",
      targets: ["SwitchGPTLifecycleActivationHost"]
    ),
  ],
  targets: [
    .target(
      name: "SwitchGPTSafetyCore"
    ),
    .target(
      name: "SwitchGPTAppCore",
      dependencies: ["SwitchGPTDesktopIntegration"]
    ),
    .target(
      name: "SwitchGPTDesktopIntegration",
      dependencies: ["SwitchGPTSafetyCore"]
    ),
    .executableTarget(
      name: "SwitchGPTApp",
      dependencies: [
        "SwitchGPTAppCore",
        "SwitchGPTDesktopIntegration",
        "SwitchGPTSafetyCore",
      ]
    ),
    .executableTarget(
      name: "SwitchGPTSafetySimulator",
      dependencies: ["SwitchGPTLifecycleContract", "SwitchGPTSafetyCore"]
    ),
    .target(
      name: "SwitchGPTLifecycleContract",
      dependencies: ["SwitchGPTSafetyCore"]
    ),
    .target(
      name: "SwitchGPTServiceManagementStatus",
      dependencies: ["SwitchGPTLifecycleContract"]
    ),
    .target(
      name: "SwitchGPTServiceManagementMutation",
      dependencies: [
        "SwitchGPTLifecycleContract",
        "SwitchGPTServiceManagementStatus",
      ]
    ),
    .executableTarget(
      name: "SwitchGPTBootRecovery",
      dependencies: ["SwitchGPTLifecycleContract", "SwitchGPTSafetyCore"],
      linkerSettings: [
        .unsafeFlags([
          "-Xlinker", "-sectcreate",
          "-Xlinker", "__TEXT",
          "-Xlinker", "__info_plist",
          "-Xlinker", "Lifecycle/BootRecovery/Info.plist",
        ])
      ]
    ),
    .executableTarget(
      name: "SwitchGPTRecoverySupervisor",
      dependencies: [
        "SwitchGPTDesktopIntegration",
        "SwitchGPTSafetyCore",
      ]
    ),
    .executableTarget(
      name: "SwitchGPTLifecycleHost",
      dependencies: ["SwitchGPTLifecycleContract", "SwitchGPTServiceManagementStatus"]
    ),
    .executableTarget(
      name: "SwitchGPTLifecycleActivationHost",
      dependencies: [
        "SwitchGPTLifecycleContract",
        "SwitchGPTServiceManagementMutation",
        "SwitchGPTServiceManagementStatus",
      ]
    ),
    .testTarget(
      name: "SwitchGPTSafetyCoreTests",
      dependencies: [
        "SwitchGPTLifecycleContract",
        "SwitchGPTSafetyCore",
        "SwitchGPTAppCore",
        "SwitchGPTDesktopIntegration",
      ]
    ),
  ]
)
