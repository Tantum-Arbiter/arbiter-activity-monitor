// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "arbiter-activity-monitor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "arbiter-activity-monitor", targets: ["ArbiterActivityMonitor"])],
    targets: [
        .target(name: "SystemProbe", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .target(name: "ArbiterCore", dependencies: ["SystemProbe"]),
        .executableTarget(name: "ArbiterActivityMonitor", dependencies: ["ArbiterCore"]),
        .testTarget(name: "ArbiterCoreTests", dependencies: ["ArbiterCore"])
    ]
)
