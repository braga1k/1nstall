import Foundation

public struct CatalogApp: Codable, Identifiable, Hashable, Sendable {
  public let id: String
  public let name: String
  public let category: String
  public let summaryEN: String
  public let summaryPT: String
  public let bundleID: String
  public let appName: String
  public let website: String
  public let source: String
  public let version: String
  public let minimumOS: String
  public let architecture: String
  public let sha256: String?
  public let verified: String
  public let supportNames: [String]
  public var automatic: Bool { source == "homebrew" }
  public init(
    id: String, name: String, category: String, summaryEN: String, summaryPT: String,
    bundleID: String, appName: String, website: String, source: String, version: String,
    minimumOS: String, architecture: String, sha256: String?, verified: String,
    supportNames: [String]
  ) {
    self.id = id
    self.name = name
    self.category = category
    self.summaryEN = summaryEN
    self.summaryPT = summaryPT
    self.bundleID = bundleID
    self.appName = appName
    self.website = website
    self.source = source
    self.version = version
    self.minimumOS = minimumOS
    self.architecture = architecture
    self.sha256 = sha256
    self.verified = verified
    self.supportNames = supportNames
  }
}
public enum Catalog {
  public static func load() throws -> [CatalogApp] {
    let packaged = Bundle.main.url(
      forResource: "OneInstallMac_OneInstallCore", withExtension: "bundle"
    ).flatMap(Bundle.init(url:))
    let resources = packaged ?? Bundle.module
    guard let url = resources.url(forResource: "catalog", withExtension: "json") else {
      throw OperationError("Catalog resource missing")
    }
    return try JSONDecoder().decode([CatalogApp].self, from: Data(contentsOf: url)).sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }
}
public struct InstalledApp: Identifiable, Codable, Hashable, Sendable {
  public var id: String { path }
  public let name: String
  public let bundleID: String
  public let path: String
  public let version: String
  public let store: Bool
  public init(name: String, bundleID: String, path: String, version: String, store: Bool) {
    self.name = name
    self.bundleID = bundleID
    self.path = path
    self.version = version
    self.store = store
  }
}
public struct InventoryResult: Sendable {
  public init() {}
  public var apps: [InstalledApp] = []
  public var warnings: [String] = []
}
public enum Inventory {
  public static var roots: [URL] {
    [
      URL(fileURLWithPath: "/Applications"),
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
      URL(fileURLWithPath: "/System/Applications"),
    ]
  }
  public static func scan(roots: [URL] = roots) -> InventoryResult {
    var result = InventoryResult()
    let fm = FileManager.default
    for root in roots where fm.fileExists(atPath: root.path) {
      guard
        let enumerator = fm.enumerator(
          at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
          options: [.skipsHiddenFiles],
          errorHandler: { url, error in
            result.warnings.append("\(url.path): \(error.localizedDescription)")
            return true
          })
      else {
        result.warnings.append(root.path)
        continue
      }
      for case let url as URL in enumerator {
        let depth = url.pathComponents.count - root.pathComponents.count
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
          enumerator.skipDescendants()
          continue
        }
        if url.pathExtension == "app" {
          enumerator.skipDescendants()
          if let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
            let id = info["CFBundleIdentifier"] as? String
          {
            result.apps.append(
              InstalledApp(
                name: info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String
                  ?? url.deletingPathExtension().lastPathComponent, bundleID: id, path: url.path,
                version: info["CFBundleShortVersionString"] as? String ?? "—",
                store: fm.fileExists(
                  atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path)))
          } else {
            result.warnings.append(url.path + ": Info.plist")
          }
        } else if depth >= 3 {
          enumerator.skipDescendants()
        }
      }
    }
    result.apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    return result
  }
}
public enum QueueStage: String, Codable, Sendable {
  case waiting, preparing, installing, authorising, stoppingServices, removing, verifying,
    succeeded, failed, guided, stopped,
    interrupted
  public var terminal: Bool {
    [.succeeded, .failed, .guided, .stopped, .interrupted].contains(self)
  }
}
public struct QueueEntry: Codable, Identifiable, Sendable {
  public let id: UUID
  public let appID: String
  public let name: String
  public let operation: String
  public var stage: QueueStage
  public var detail: String
  public var date: Date
  public var removedApp: RemovalIdentity?
  public var removalMethod: RemovalMethod?
  public var trashPath: String?
  public var recoveryPath: String?
  public init(app: CatalogApp, operation: String) {
    id = UUID()
    appID = app.id
    name = app.name
    self.operation = operation
    stage = .waiting
    detail = ""
    date = Date()
  }
  public init(
    cleanup identity: RemovalIdentity, detail: String, succeeded: Bool,
    operation: String = "cleanup"
  ) {
    id = UUID()
    appID = identity.id
    name = identity.name
    self.operation = operation
    stage = succeeded ? .succeeded : .failed
    self.detail = detail
    date = Date()
    removedApp = identity
  }
  public init(plan: RemovalPlan) {
    id = UUID()
    appID = plan.identity.id
    name = plan.identity.name
    operation = "remove"
    stage = .waiting
    detail = ""
    date = Date()
    removedApp = plan.identity
    removalMethod = plan.method
  }
}
public struct SavedState: Codable {
  public var installSelection: Set<String> = []
  public var removalSelection: Set<String> = []
  public var queue: [QueueEntry] = []
  public var history: [QueueEntry] = []
  public var receipts: [String: String] = [:]
  public init() {}
}
public enum Persistence {
  public static func save(_ state: SavedState, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(state).write(to: url, options: .atomic)
  }
  public static func read(_ url: URL) throws -> SavedState {
    var state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
    for i in state.queue.indices where !state.queue[i].stage.terminal {
      state.queue[i].stage = .interrupted
    }
    return state
  }
}
