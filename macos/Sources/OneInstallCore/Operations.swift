import AppKit
import Foundation

public struct OperationError: LocalizedError {
  public let message: String
  public var errorDescription: String? { message }
  public init(_ message: String) { self.message = message }
}
public struct CommandResult: Sendable {
  public let code: Int32
  public let output: String
}
public enum Command {
  // No shell interpolation. stdout/stderr share a draining pipe; stdin cannot request a password.
  public static func run(
    _ executable: String, _ arguments: [String], timeout: TimeInterval = 900,
    onOutput: @escaping (String) -> Void = { _ in }
  ) throws -> CommandResult {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    var env = ProcessInfo.processInfo.environment
    env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
    env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
    env["HOMEBREW_NO_ANALYTICS"] = "1"
    env["NONINTERACTIVE"] = "1"
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    process.environment = env
    process.standardOutput = pipe
    process.standardError = pipe
    process.standardInput = FileHandle.nullDevice
    try process.run()
    let lock = NSLock()
    var expired = false
    let timeoutWork = DispatchWorkItem {
      lock.lock()
      defer { lock.unlock() }
      if process.isRunning {
        expired = true
        process.terminate()
      }
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
    var output = Data()
    while true {
      let data = pipe.fileHandleForReading.availableData
      if data.isEmpty { break }
      onOutput(String(decoding: data, as: UTF8.self))
      output.append(data)
      if output.count > 2_000_000 { output.removeFirst(output.count - 2_000_000) }
    }
    process.waitUntilExit()
    timeoutWork.cancel()
    lock.lock()
    let timedOut = expired
    lock.unlock()
    if timedOut {
      throw OperationError("Command timed out. Check the app and Homebrew before retrying.")
    }
    return CommandResult(
      code: process.terminationStatus, output: String(decoding: output, as: UTF8.self))
  }
}
public struct BrewEngine: Sendable {
  public let executable: String
  public let appDirectory: URL
  public init(executable: String? = nil, appDirectory: URL = URL(fileURLWithPath: "/Applications"))
  {
    self.executable =
      executable
      ?? (["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first {
        FileManager.default.isExecutableFile(atPath: $0)
      } ?? "/opt/homebrew/bin/brew")
    self.appDirectory = appDirectory
  }
  public var available: Bool { FileManager.default.isExecutableFile(atPath: executable) }
  public func preflight(_ app: CatalogApp, removal: Bool = false) throws {
    guard available, app.automatic,
      app.id.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil
    else { throw OperationError("Homebrew or a reviewed cask is unavailable.") }
    let r = try Command.run(executable, ["info", "--json=v2", "--cask", app.id], timeout: 90)
    guard r.code == 0, let d = r.output.data(using: .utf8),
      let json = try JSONSerialization.jsonObject(with: d) as? [String: Any],
      let cask = (json["casks"] as? [[String: Any]])?.first,
      cask["disabled"] as? Bool != true, cask["deprecated"] as? Bool != true
    else { throw OperationError("The cask is unavailable or no longer maintained.") }
    guard
      removal
        || (cask["version"] as? String == app.version && cask["sha256"] as? String == app.sha256)
    else {
      throw OperationError("The cask changed since review. Update the catalog before installing.")
    }
    let allowed: Set<String> = ["app", "binary", "command_wrapper", "uninstall", "zap", "target"]
    guard let artifacts = cask["artifacts"] as? [[String: Any]],
      artifacts.allSatisfy({ Set($0.keys).isSubset(of: allowed) })
    else { throw OperationError("This installer needs a separate review.") }
    let bundles = artifacts.compactMap { $0["app"] as? [Any] }
    guard bundles.count == 1, let first = bundles[0].first as? String else {
      throw OperationError("This installer needs a separate review.")
    }
    let renamed = bundles[0].compactMap { $0 as? [String: String] }.first?["target"]
    guard (renamed ?? first) == app.appName,
      URL(fileURLWithPath: app.appName).lastPathComponent == app.appName,
      app.appName.hasSuffix(".app")
    else { throw OperationError("The installed app name changed after review.") }
    for artifact in artifacts {
      if let actions = artifact["uninstall"] as? [[String: Any]],
        !actions.allSatisfy({ Set($0.keys).isSubset(of: ["quit", "login_item"]) })
      {
        throw OperationError("The uninstaller requires a separate review.")
      }
    }
    guard ProcessInfo.processInfo.operatingSystemVersionString.count > 0,
      app.minimumOS.compare(
        "\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)",
        options: .numeric) != .orderedDescending
    else { throw OperationError("This macOS version is not supported by the app.") }
  }
  public func install(
    _ app: CatalogApp, inventoryRoots: [URL] = Inventory.roots, onStage: (QueueStage) -> Void,
    log: @escaping (String) -> Void
  ) throws -> String {
    onStage(.preparing)
    try preflight(app)
    let existing = Inventory.scan(roots: inventoryRoots)
    guard existing.warnings.isEmpty else {
      throw OperationError("Inventory is incomplete. Resolve access errors before installation.")
    }
    let destination = appDirectory.appendingPathComponent(app.appName)
    guard !existing.apps.contains(where: { $0.bundleID == app.bundleID }),
      !FileManager.default.fileExists(atPath: destination.path)
    else { throw OperationError("This app already exists. It was preserved.") }
    let receipt = try Command.run(executable, ["list", "--cask", "--versions"], timeout: 30)
    guard receipt.code == 0,
      !receipt.output.split(separator: "\n").contains(where: {
        $0.split(separator: " ").first == Substring(app.id)
      })
    else {
      throw OperationError("Homebrew already manages this cask. Existing installation preserved.")
    }
    onStage(.installing)
    let r = try Command.run(
      executable, ["install", "--cask", "--appdir=\(appDirectory.path)", app.id], onOutput: log)
    onStage(.verifying)
    guard r.code == 0,
      let info = NSDictionary(
        contentsOf: destination.appendingPathComponent("Contents/Info.plist")),
      info["CFBundleIdentifier"] as? String == app.bundleID,
      let binary = info["CFBundleExecutable"] as? String
    else {
      throw OperationError("Installation was not confirmed. Inspect the log and refresh inventory.")
    }
    let executablePath = destination.appendingPathComponent("Contents/MacOS")
      .appendingPathComponent(binary).path
    let arch = try Command.run("/usr/bin/lipo", ["-archs", executablePath], timeout: 30)
    guard arch.code == 0, arch.output.contains("arm64") else {
      throw OperationError("Apple Silicon support was not confirmed. Inspect the installed app.")
    }
    return destination.path
  }
}
