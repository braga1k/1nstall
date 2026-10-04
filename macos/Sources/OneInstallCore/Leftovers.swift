import AppKit
import CryptoKit
import Foundation

public enum DataKind: String, Codable, Sendable { case regenerable, personal, shared, system }
public struct Leftover: Identifiable, Sendable {
  public var id: String { url.path }
  public let url: URL
  public let kind: DataKind
  public let bytes: Int64
  public let files: Int
  public let complete: Bool
  public let fingerprint: String
  public let reason: String
  public var selectable: Bool { complete && kind != .shared && kind != .system }
}
public struct LeftoverReport: Sendable {
  public init() {}
  public var items: [Leftover] = []
  public var warnings: [String] = []
}
public struct LeftoverScanner: Sendable {
  public let home: URL
  public let systemLibrary: URL?
  public init(
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    systemLibrary: URL? = URL(fileURLWithPath: "/Library")
  ) {
    self.home = home.standardizedFileURL
    self.systemLibrary = systemLibrary?.standardizedFileURL
  }
  private struct Candidate {
    let relative: String
    let kind: DataKind
    let reason: String
  }
  private func validID(_ value: String) -> Bool {
    value.range(of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil
  }
  private func names(_ app: InstalledApp) -> Set<String> {
    let stem = URL(fileURLWithPath: app.path).deletingPathExtension().lastPathComponent
    let blocked: Set<String> = [
      "apple", "google", "microsoft", "adobe", "application support", "applications", "cache",
      "caches", "logs", "preferences", "shared", "data", "library", "local", "common", "support",
      "containers",
    ]
    return Set(
      [app.name, stem].filter {
        $0.count >= 4 && !$0.contains("/") && !$0.contains("..")
          && !blocked.contains($0.lowercased())
          && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
      })
  }
  private func definitions(_ identity: RemovalIdentity, installed: [InstalledApp]) -> [Candidate] {
    let id = identity.bundleID
    guard validID(id), RemovalEngine.protection(identity.app) == nil else { return [] }
    var candidates: [Candidate] = []
    func add(_ path: String, _ kind: DataKind, _ reason: String = "bundle") {
      candidates.append(Candidate(relative: path, kind: kind, reason: reason))
    }
    for path in ["Caches/\(id)", "Logs/\(id)", "HTTPStorages/\(id)", "WebKit/\(id)"] {
      add(path, .regenerable)
    }
    for path in [
      "Saved Application State/\(id).savedState", "Preferences/\(id).plist",
      "Application Support/\(id)", "HTTPStorages/\(id).binarycookies",
      "Cookies/\(id).binarycookies",
      "Application Scripts/\(id)", "SyncedPreferences/\(id).plist", "Autosave Information/\(id)",
    ] { add(path, .personal) }
    let container = home.appendingPathComponent("Library/Containers/\(id)")
    let metadata = container.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
    let confirmedContainer =
      safe(metadata)
      && (NSDictionary(contentsOf: metadata)?["MCMMetadataIdentifier"] as? String == id)
    add(
      "Containers/\(id)", confirmedContainer ? .personal : .shared,
      confirmedContainer ? "container" : "unverifiedContainer")
    for group in identity.groupIDs.filter({ validID($0) }) {
      add("Group Containers/\(group)", .shared, "group")
      add("Application Scripts/\(group)", .shared, "group")
    }
    let otherNames = installed.filter { $0.bundleID != id }.reduce(into: Set<String>()) {
      set, app in
      set.formUnion(names(app).map { $0.lowercased() })
    }
    let reviewed = identity.supportNames.filter {
      !$0.contains("/") && !$0.contains("..") && !$0.isEmpty
    }
    for name in names(identity.app).union(reviewed) {
      let shared = otherNames.contains(name.lowercased()) || id.hasPrefix("com.apple.")
      add(
        "Application Support/\(name)", shared ? .shared : .personal, shared ? "sharedName" : "name")
      for folder in ["Caches", "Logs"] {
        add("\(folder)/\(name)", shared ? .shared : .regenerable, shared ? "sharedName" : "name")
      }
    }
    // ByHost preferences use a strict UUID suffix, never a broad bundle prefix glob.
    let byHost = home.appendingPathComponent("Library/Preferences/ByHost")
    if safe(byHost),
      let entries = try? FileManager.default.contentsOfDirectory(
        at: byHost, includingPropertiesForKeys: nil)
    {
      for entry in entries where entry.pathExtension == "plist" {
        let stem = entry.deletingPathExtension().lastPathComponent
        if stem.hasPrefix(id + "."), UUID(uuidString: String(stem.dropFirst(id.count + 1))) != nil {
          add("Preferences/ByHost/" + entry.lastPathComponent, .personal)
        }
      }
    }
    let agents = home.appendingPathComponent("Library/LaunchAgents")
    if safe(agents),
      let entries = try? FileManager.default.contentsOfDirectory(
        at: agents, includingPropertiesForKeys: nil)
    {
      for entry in entries where entry.pathExtension == "plist" && safe(entry) {
        guard let plist = NSDictionary(contentsOf: entry), let label = plist["Label"] as? String,
          validID(label), !label.hasPrefix("com.apple."),
          let program = (plist["Program"] as? String)
            ?? (plist["ProgramArguments"] as? [String])?.first,
          program.hasPrefix(identity.app.path + "/"),
          URL(fileURLWithPath: program).standardizedFileURL.path == program
        else { continue }
        add("LaunchAgents/" + entry.lastPathComponent, .personal, "launchAgent")
      }
    }
    // Deduplicate before measuring; shared always wins when associations collide.
    var unique: [String: Candidate] = [:]
    for candidate in candidates {
      if unique[candidate.relative]?.kind != .shared { unique[candidate.relative] = candidate }
    }
    return unique.values.sorted { $0.relative < $1.relative }
  }
  private func safe(_ url: URL) -> Bool {
    let lib = home.appendingPathComponent("Library").standardizedFileURL
    guard url.path.hasPrefix(lib.path + "/"), url.resolvingSymlinksInPath().path == url.path,
      lib.resolvingSymlinksInPath().path == lib.path
    else { return false }
    return true
  }
  public func scan(_ app: CatalogApp) -> LeftoverReport { scan(RemovalIdentity(catalog: app)) }
  public func scan(_ identity: RemovalIdentity, installed: [InstalledApp] = []) -> LeftoverReport {
    var report = LeftoverReport()
    for candidate in definitions(identity, installed: installed) {
      let url = home.appendingPathComponent("Library").appendingPathComponent(candidate.relative)
      do {
        _ = try FileManager.default.attributesOfItem(atPath: url.path)
        guard safe(url) else {
          report.warnings.append("Protected link: \(url.path)")
          continue
        }
        let item = try measure(url, kind: candidate.kind, reason: candidate.reason)
        report.items.append(item)
        if !item.complete { report.warnings.append("Partial measurement: \(url.path)") }
      } catch let error as NSError {
        if error.domain != NSCocoaErrorDomain || error.code != NSFileReadNoSuchFileError {
          report.warnings.append("\(url.path): \(error.localizedDescription)")
        }
      }
    }
    if let systemLibrary, validID(identity.bundleID), RemovalEngine.protection(identity.app) == nil,
      systemLibrary.resolvingSymlinksInPath().path == systemLibrary.path
    {
      var paths = [
        "Preferences/\(identity.bundleID).plist", "Application Support/\(identity.bundleID)",
        "Caches/\(identity.bundleID)", "Logs/\(identity.bundleID)",
      ]
      paths += names(identity.app).map { "Application Support/" + $0 }
      for folder in ["LaunchAgents", "LaunchDaemons"] {
        let root = systemLibrary.appendingPathComponent(folder)
        if root.resolvingSymlinksInPath().path == root.path,
          let entries = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)
        {
          for entry in entries
          where entry.pathExtension == "plist" && entry.resolvingSymlinksInPath().path == entry.path
          {
            if let plist = NSDictionary(contentsOf: entry),
              let program = (plist["Program"] as? String)
                ?? (plist["ProgramArguments"] as? [String])?.first,
              program.hasPrefix(identity.app.path + "/"),
              URL(fileURLWithPath: program).standardizedFileURL.path == program
            {
              paths.append(folder + "/" + entry.lastPathComponent)
            }
          }
        }
      }
      for relative in Set(paths).sorted() {
        let url = systemLibrary.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else { continue }
        do {
          guard url.resolvingSymlinksInPath().path == url.path else {
            throw OperationError("Protected link")
          }
          let item = try measure(url, kind: .system, reason: "system")
          report.items.append(item)
          if !item.complete { report.warnings.append("Partial measurement: \(url.path)") }
        } catch { report.warnings.append("\(url.path): \(error.localizedDescription)") }
      }
    }
    return report
  }
  private func measure(_ root: URL, kind: DataKind, reason: String) throws -> Leftover {
    var bytes: Int64 = 0
    var files = 0
    var count = 0
    var complete = true
    var parts: [String] = []
    func record(_ url: URL) throws {
      count += 1
      let a = try FileManager.default.attributesOfItem(atPath: url.path)
      if a[.type] as? FileAttributeType == .typeSymbolicLink {
        complete = false
        return
      }
      if a[.type] as? FileAttributeType == .typeRegular {
        bytes += (a[.size] as? NSNumber)?.int64Value ?? 0
        files += 1
      }
      parts.append(
        "\(url.path)|\(a[.systemNumber] ?? "")|\(a[.systemFileNumber] ?? "")|\(a[.size] ?? "")|\((a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
      )
    }
    try record(root)
    if (try FileManager.default.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType)
      == .typeDirectory,
      let e = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isSymbolicLinkKey],
        errorHandler: { _, _ in
          complete = false
          return true
        })
    {
      for case let u as URL in e {
        if count >= 20_000 {
          complete = false
          break
        }
        do {
          try record(u)
          if u.resolvingSymlinksInPath().path != u.path || !u.path.hasPrefix(root.path + "/") {
            e.skipDescendants()
            complete = false
          }
        } catch { complete = false }
      }
    }
    let hash = SHA256.hash(data: Data(parts.sorted().joined(separator: "\n").utf8)).map {
      String(format: "%02x", $0)
    }.joined()
    return Leftover(
      url: root, kind: kind, bytes: bytes, files: files, complete: complete, fingerprint: hash,
      reason: reason)
  }
  public func trash(_ item: Leftover, for app: CatalogApp, installed: [InstalledApp]) throws -> URL
  {
    try trash(item, for: RemovalIdentity(catalog: app), installed: installed)
  }
  public func trash(_ item: Leftover, for identity: RemovalIdentity, installed: [InstalledApp])
    throws -> URL
  {
    guard
      installed.allSatisfy({ $0.bundleID != identity.bundleID && $0.path != identity.app.path }),
      NSRunningApplication.runningApplications(withBundleIdentifier: identity.bundleID).isEmpty,
      !FileManager.default.fileExists(atPath: identity.app.path)
    else { throw OperationError("An installed or running copy still uses these data.") }
    guard item.selectable, safe(item.url),
      definitions(identity, installed: installed).contains(where: {
        home.appendingPathComponent("Library").appendingPathComponent($0.relative) == item.url
          && $0.kind == item.kind && $0.reason == item.reason
      })
    else { throw OperationError("Protected, shared or unreviewed path.") }
    let current = try measure(item.url, kind: item.kind, reason: item.reason)
    guard current.complete, current.fingerprint == item.fingerprint else {
      throw OperationError("Files changed after review. Scan again.")
    }
    if item.reason == "launchAgent" {
      guard let plist = NSDictionary(contentsOf: item.url), let label = plist["Label"] as? String,
        validID(label)
      else { throw OperationError("The launch agent changed after review.") }
      let service = "gui/\(getuid())/\(label)"
      let loaded = try Command.run("/bin/launchctl", ["print", service], timeout: 10)
      if loaded.code == 0 {
        let result = try Command.run(
          "/bin/launchctl", ["bootout", "gui/\(getuid())", item.url.path], timeout: 15)
        guard result.code == 0 else {
          throw OperationError(
            "The background service could not be stopped. Its file was preserved.")
        }
      } else if loaded.code != 113 {
        throw OperationError("The background service state is unknown. Its file was preserved.")
      }
      let after = try Command.run("/bin/launchctl", ["print", service], timeout: 10)
      guard after.code == 113 else {
        throw OperationError("The background service is still registered.")
      }
      guard safe(item.url),
        try measure(item.url, kind: item.kind, reason: item.reason).fingerprint == item.fingerprint,
        !FileManager.default.fileExists(atPath: identity.app.path)
      else {
        throw OperationError(
          "Files changed while the background service was stopping. Review again.")
      }
    }
    var resulting: NSURL?
    try FileManager.default.trashItem(at: item.url, resultingItemURL: &resulting)
    guard !FileManager.default.fileExists(atPath: item.url.path),
      let destination = resulting as URL?, FileManager.default.fileExists(atPath: destination.path)
    else { throw OperationError("Moving to Trash was not confirmed.") }
    return destination
  }
}
