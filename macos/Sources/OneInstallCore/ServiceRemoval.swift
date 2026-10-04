import AppKit
import CryptoKit
import Foundation

/// Files are pinned to the reviewed object, not just its name. Never follows a link.
public enum FileIdentity {
  public static func snapshot(_ url: URL) throws -> String {
    guard url.standardizedFileURL.path == url.path,
      url.resolvingSymlinksInPath().path == url.path
    else { throw OperationError("A reviewed path is a symbolic link or changed location.") }
    let fm = FileManager.default
    let attributes = try fm.attributesOfItem(atPath: url.path)
    let parent = try fm.attributesOfItem(atPath: url.deletingLastPathComponent().path)
    var data = Data(
      "\(url.path)|\(attributes[.systemNumber] ?? "")|\(attributes[.systemFileNumber] ?? "")|\(attributes[.size] ?? "")|\(attributes[.modificationDate] ?? "")|\(parent[.systemNumber] ?? "")|\(parent[.systemFileNumber] ?? "")"
        .utf8)
    if attributes[.type] as? FileAttributeType == .typeRegular {
      guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max < 4_000_000 else {
        throw OperationError("The reviewed metadata is too large.")
      }
      data.append(try Data(contentsOf: url))
    }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  public static func validLabel(_ label: String) -> Bool {
    label.range(of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil
      && !label.hasPrefix("com.apple.")
  }
}

public struct AssociatedService: Codable, Hashable, Identifiable, Sendable {
  public var id: String { domain + "/" + label }
  public let path: String
  public let label: String
  public let program: String
  public let domain: String
  public let fingerprint: String
  public let privileged: Bool
  public let loaded: Bool
}

public struct ServiceRemoval: Sendable {
  public let home: URL
  public let systemLibrary: URL
  public let uid: UInt32
  public init(
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    systemLibrary: URL = URL(fileURLWithPath: "/Library"), uid: UInt32 = getuid()
  ) {
    self.home = home
    self.systemLibrary = systemLibrary
    self.uid = uid
  }
  public func discover(_ identity: RemovalIdentity, probe: Bool = true) throws
    -> [AssociatedService]
  {
    let app = URL(fileURLWithPath: identity.app.path)
    let folders: [(URL, String, Bool)] = [
      (home.appendingPathComponent("Library/LaunchAgents"), "gui/\(uid)", false),
      (systemLibrary.appendingPathComponent("LaunchAgents"), "gui/\(uid)", false),
      (systemLibrary.appendingPathComponent("LaunchDaemons"), "system", true),
      (app.appendingPathComponent("Contents/Library/LaunchAgents"), "gui/\(uid)", false),
      (app.appendingPathComponent("Contents/Library/LaunchDaemons"), "system", true),
    ]
    var result: [AssociatedService] = []
    for (folder, domain, privileged) in folders {
      guard FileManager.default.fileExists(atPath: folder.path) else { continue }
      guard folder.resolvingSymlinksInPath().path == folder.path else {
        throw OperationError("A service directory is a symbolic link. Review its location first.")
      }
      for url in try FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil)
      where url.pathExtension == "plist" {
        guard
          let service = try inspect(
            url, identity: identity, domain: domain, privileged: privileged, probe: probe)
        else { continue }
        if let other = result.first(where: { $0.id == service.id }), other.path != service.path {
          throw OperationError(
            "Several files claim the same background service. Resolve the conflict first.")
        }
        result.append(service)
      }
    }
    return result.sorted { $0.id < $1.id }
  }
  private func inspect(
    _ url: URL, identity: RemovalIdentity, domain: String, privileged: Bool,
    probe: Bool
  ) throws -> AssociatedService? {
    guard url.resolvingSymlinksInPath().path == url.path,
      let plist = NSDictionary(contentsOf: url), let label = plist["Label"] as? String,
      FileIdentity.validLabel(label)
    else { return nil }
    var program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first
    if program == nil, url.path.hasPrefix(identity.app.path + "/Contents/Library/"),
      let relative = plist["BundleProgram"] as? String, !relative.hasPrefix("/")
    {
      program = identity.app.path + "/" + relative
    }
    guard let program, program.hasPrefix(identity.app.path + "/"),
      URL(fileURLWithPath: program).standardizedFileURL.path == program,
      URL(fileURLWithPath: program).resolvingSymlinksInPath().path == program
    else { return nil }
    let loaded = probe ? try state(domain + "/" + label, expectedProgram: program) : false
    return AssociatedService(
      path: url.path, label: label, program: program, domain: domain,
      fingerprint: try FileIdentity.snapshot(url), privileged: privileged, loaded: loaded)
  }
  public func state(_ target: String, expectedProgram: String) throws -> Bool {
    let result = try Command.run("/bin/launchctl", ["print", target], timeout: 10)
    if result.code == 113 { return false }
    guard result.code == 0 else {
      throw OperationError("The background service state could not be verified.")
    }
    let programs = result.output.split(separator: "\n").compactMap { line -> String? in
      let value = line.trimmingCharacters(in: .whitespaces)
      guard value.hasPrefix("program = ") else { return nil }
      return String(value.dropFirst(10)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
    guard programs == [expectedProgram] else {
      throw OperationError("A loaded service belongs to another executable. It was preserved.")
    }
    return true
  }
  public func validate(_ service: AssociatedService, identity: RemovalIdentity) throws {
    let current = try discover(identity, probe: false)
    guard
      current.contains(where: {
        $0.id == service.id && $0.path == service.path && $0.program == service.program
          && $0.fingerprint == service.fingerprint && $0.privileged == service.privileged
      })
    else { throw OperationError("The background service changed after review.") }
  }
  public func stop(_ service: AssociatedService, identity: RemovalIdentity) throws {
    try validate(service, identity: identity)
    if try state(service.id, expectedProgram: service.program) {
      let result = try Command.run("/bin/launchctl", ["bootout", service.id], timeout: 20)
      guard result.code == 0 else {
        throw OperationError("The background service could not be stopped. Its app was preserved.")
      }
    }
    guard try !state(service.id, expectedProgram: service.program) else {
      throw OperationError("The background service is still registered.")
    }
    try validate(service, identity: identity)
  }
}
