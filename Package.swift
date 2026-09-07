// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SignalMonitor",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "SignalMonitor", targets: ["SignalMonitor"])],
    targets: [
        .executableTarget(
            name: "SignalMonitor",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "SignalMonitorTests", dependencies: ["SignalMonitor"])
    ]
)
