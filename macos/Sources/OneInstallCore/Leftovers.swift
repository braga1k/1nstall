import AppKit
import CryptoKit
import Foundation

public enum DataKind: String, Codable, Sendable { case regenerable, personal, shared }
public struct Leftover: Identifiable, Sendable {
  public var id: String { url.path }
  public let url: URL
  public let kind: DataKind
  public let bytes: Int64
  public let files: Int
  public let complete: Bool
  public let fingerprint: String
  public let reason: String
  public var selectable: Bool { complete && kind != .shared }
}
public struct LeftoverReport: Sendable {
  public init() {}
  public var items: [Leftover] = []
  public var warnings: [String] = []
}
public struct LeftoverScanner: Sendable {
  public let home: URL
  public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
    self.home = home.standardizedFileURL
  }
  private func definitions(_ app: CatalogApp) -> [(String, DataKind)] {
    let id = app.bundleID
    guard id.range(of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+){2,}$", options: .regularExpression) != nil,
      !id.hasPrefix("com.apple.")
    else { return [] }
    return [
      ("Caches/\(id)", .regenerable), ("Logs/\(id)", .regenerable),
      ("HTTPStorages/\(id)", .regenerable), ("Saved Application State/\(id).savedState", .personal),
      ("Preferences/\(id).plist", .personal), ("Application Support/\(id)", .personal),
      ("Containers/\(id)", .shared),
    ]
      + app.supportNames.filter { !$0.contains("/") && !$0.contains("..") && !$0.isEmpty }.map {
        ("Application Support/\($0)", .personal)
      }
  }
  private func safe(_ url: URL) -> Bool {
    let lib = home.appendingPathComponent("Library").standardizedFileURL
    guard url.path.hasPrefix(lib.path + "/"), url.resolvingSymlinksInPath().path == url.path,
      lib.resolvingSymlinksInPath().path == lib.path
    else { return false }
    return true
  }
  public func scan(_ app: CatalogApp) -> LeftoverReport {
    var report = LeftoverReport()
    for (relative, kind) in definitions(app) {
      let url = home.appendingPathComponent("Library").appendingPathComponent(relative)
      do {
        _ = try FileManager.default.attributesOfItem(atPath: url.path)
        guard safe(url) else {
          report.warnings.append("Protected link: \(url.path)")
          continue
        }
        let item = try measure(url, kind: kind)
        report.items.append(item)
        if !item.complete { report.warnings.append("Partial measurement: \(url.path)") }
      } catch let error as NSError {
        if error.domain != NSCocoaErrorDomain || error.code != NSFileReadNoSuchFileError {
          report.warnings.append("\(url.path): \(error.localizedDescription)")
        }
      }
    }
    return report
  }
  private func measure(_ root: URL, kind: DataKind) throws -> Leftover {
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
          if !safe(u) {
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
      reason: "Exact reviewed path; association does not prove exclusive ownership.")
  }
  public func trash(_ item: Leftover, for app: CatalogApp, installed: [InstalledApp]) throws -> URL
  {
    guard installed.allSatisfy({ $0.bundleID != app.bundleID }),
      NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    else { throw OperationError("An installed or running copy still uses these data.") }
    guard item.selectable, safe(item.url),
      definitions(app).contains(where: {
        home.appendingPathComponent("Library").appendingPathComponent($0.0) == item.url
          && $0.1 == item.kind
      })
    else { throw OperationError("Protected or unreviewed path.") }
    let current = try measure(item.url, kind: item.kind)
    guard current.complete, current.fingerprint == item.fingerprint else {
      throw OperationError("Files changed after review. Scan again.")
    }
    var resulting: NSURL?
    try FileManager.default.trashItem(at: item.url, resultingItemURL: &resulting)
    guard !FileManager.default.fileExists(atPath: item.url.path),
      let destination = resulting as URL?
    else { throw OperationError("Moving to Trash was not confirmed.") }
    return destination
  }
}
