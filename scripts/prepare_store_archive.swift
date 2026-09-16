import Foundation

// Normalize CMake's macOS archive wrapper without altering the signed app.
// Usage: swift scripts/prepare_store_archive.swift path/to/archive.xcarchive
func run(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "ArchivePreparation", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: output])
    }
    return output
}

func plist(_ url: URL) throws -> [String: Any] {
    guard let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any] else {
        throw NSError(domain: "ArchivePreparation", code: 2)
    }
    return value
}

guard CommandLine.arguments.count == 2 else { fatalError("Supply one .xcarchive path") }
let archive = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
guard archive.pathExtension == "xcarchive" else { fatalError("Expected .xcarchive") }
let fm = FileManager.default
let applications = archive.appendingPathComponent("Products/Applications")
let apps = try fm.contentsOfDirectory(at: applications, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
guard apps.count == 1, let app = apps.first else { fatalError("Expected exactly one app") }
let appInfo = try plist(app.appendingPathComponent("Contents/Info.plist"))
guard appInfo["CFBundleIdentifier"] as? String == "com.caiyuli.signalmonitor",
      let executable = appInfo["CFBundleExecutable"] as? String,
      let version = appInfo["CFBundleShortVersionString"] as? String,
      let build = appInfo["CFBundleVersion"] as? String else { fatalError("Unexpected app metadata") }
_ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
let signature = try run("/usr/bin/codesign", ["-dvv", app.path])
guard signature.contains("TeamIdentifier=2YT8NRXC26") else { fatalError("Unexpected signing team") }
let identity = signature.components(separatedBy: "\n").first { $0.hasPrefix("Authority=") }?.dropFirst("Authority=".count)
guard let identity else { fatalError("Expected certificate-based signing") }

let misplaced = applications.appendingPathComponent(app.lastPathComponent + ".dSYM")
let symbols = archive.appendingPathComponent("dSYMs")
let destination = symbols.appendingPathComponent(app.lastPathComponent + ".dSYM")
func uuids(_ url: URL) throws -> [String] {
    try run("/usr/bin/xcrun", ["dwarfdump", "--uuid", url.path])
        .components(separatedBy: "\n").filter { $0.hasPrefix("UUID:") }
        .map { $0.components(separatedBy: " ").prefix(3).joined(separator: " ") }.sorted()
}
let binaryUUIDs = try uuids(app.appendingPathComponent("Contents/MacOS/" + executable))
let source = fm.fileExists(atPath: misplaced.path) ? misplaced : destination
guard !binaryUUIDs.isEmpty, try uuids(source) == binaryUUIDs else { fatalError("Mismatched symbols") }
if source == misplaced {
    guard !fm.fileExists(atPath: destination.path) else { fatalError("Symbol destination already exists") }
    try fm.createDirectory(at: symbols, withIntermediateDirectories: true)
    try fm.moveItem(at: misplaced, to: destination)
}
let infoURL = archive.appendingPathComponent("Info.plist")
var info = try plist(infoURL)
info["ApplicationProperties"] = [
    "ApplicationPath": "Applications/" + app.lastPathComponent,
    "CFBundleIdentifier": "com.caiyuli.signalmonitor",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": build,
    "SigningIdentity": String(identity),
    "Team": "2YT8NRXC26"
]
try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL, options: .atomic)
print("Prepared signed archive \(version) (\(build)); matching symbols verified.")
