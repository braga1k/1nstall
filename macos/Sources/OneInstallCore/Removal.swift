import AppKit
import CryptoKit
import Foundation
import Security

/// Retained with the result so data can be reviewed after the bundle is gone.
public struct RemovalIdentity: Codable, Hashable, Identifiable, Sendable {
  public var id: String { app.path }
  public let app: InstalledApp
  public let supportNames: [String]
  public let groupIDs: [String]
  public init(app: InstalledApp, supportNames: [String] = [], groupIDs: [String] = []) {
    self.app = app
    self.supportNames = supportNames
    self.groupIDs = groupIDs
  }
  public static func inspect(_ app: InstalledApp, catalog: [CatalogApp]) -> RemovalIdentity {
    var groups: [String] = []
    var code: SecStaticCode?
    if SecStaticCodeCreateWithPath(URL(fileURLWithPath: app.path) as CFURL, [], &code)
      == errSecSuccess,
      let code, SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
    {
      var signing: CFDictionary?
      if SecCodeCopySigningInformation(
        code, SecCSFlags(rawValue: kSecCSSigningInformation), &signing) == errSecSuccess,
        let dictionary = signing as? [String: Any],
        let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
      {
        groups = entitlements["com.apple.security.application-groups"] as? [String] ?? []
      }
    }
    return RemovalIdentity(
      app: app,
      supportNames: catalog.first { $0.bundleID == app.bundleID }?.supportNames ?? [],
      groupIDs: groups)
  }
  public var name: String { app.name }
  public var bundleID: String { app.bundleID }
  public init(catalog: CatalogApp) {
    self.init(
      app: InstalledApp(
        name: catalog.name, bundleID: catalog.bundleID,
        path: "/Applications/" + catalog.appName, version: catalog.version, store: false),
      supportNames: catalog.supportNames)
  }
}

public enum RemovalMethod: String, Codable, Sendable { case trash, homebrew }
public struct RemovalPlan: Identifiable, Sendable {
  public var id: String { identity.id }
  public let identity: RemovalIdentity
  public let method: RemovalMethod
  public let cask: String?
  public let fingerprint: String
  public let caskFingerprint: String?
}
public struct RemovalResult: Sendable {
  public let trashPath: String?
  public let remainingCopies: Int
}

/// Filesystem evidence only; never guesses a cask from an application's name.
public struct CaskIndex: Sendable {
  public static let rooms = ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"].map {
    URL(fileURLWithPath: $0)
  }
  public var owners: [String: Set<String>] = [:]
  public var warnings: [String] = []
  public init(rooms: [URL] = rooms) {
    var issues: [String] = []
    let fm = FileManager.default
    for room in rooms where fm.fileExists(atPath: room.path) {
      guard room.resolvingSymlinksInPath().path == room.path else {
        issues.append("Caskroom is a symbolic link: \(room.path)")
        continue
      }
      guard
        let tokens = try? fm.contentsOfDirectory(
          at: room, includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles])
      else {
        issues.append("Cannot read \(room.path)")
        continue
      }
      for token in tokens where Self.validToken(token.lastPathComponent) {
        guard
          let e = fm.enumerator(
            at: token, includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles],
            errorHandler: { url, _ in
              issues.append("Cannot inspect \(url.path)")
              return false
            })
        else {
          issues.append("Cannot inspect \(token.path)")
          continue
        }
        for case let url as URL in e {
          if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            e.skipDescendants()
            if url.pathExtension.lowercased() == "app" {
              owners[url.resolvingSymlinksInPath().path, default: []].insert(
                token.lastPathComponent)
            }
          } else if url.pathExtension.lowercased() == "app" {
            e.skipDescendants()
          } else if url.pathComponents.count - token.pathComponents.count >= 2 {
            e.skipDescendants()
          }
        }
      }
    }
    warnings = issues
  }
  public static func validToken(_ token: String) -> Bool {
    token.range(of: "^[a-z0-9][a-z0-9+@._-]*$", options: .regularExpression) != nil
  }
}

public struct RemovalEngine: Sendable {
  public let roots: [URL]
  public let caskRooms: [URL]
  public let brew: BrewEngine
  public init(
    roots: [URL] = Inventory.roots, caskRooms: [URL] = CaskIndex.rooms,
    brew: BrewEngine = BrewEngine()
  ) {
    self.roots = roots
    self.caskRooms = caskRooms
    self.brew = brew
  }
  public static func protection(_ app: InstalledApp) -> String? {
    if app.path.hasPrefix("/System/") { return "system" }
    if app.bundleID == Bundle.main.bundleIdentifier || app.path == Bundle.main.bundlePath {
      return "self"
    }
    if app.bundleID.hasPrefix("com.apple.") {
      let downloadable = [
        "com.apple.dt.", "com.apple.FinalCut", "com.apple.Motion", "com.apple.Compressor",
        "com.apple.logic", "com.apple.garageband", "com.apple.iMovie", "com.apple.iWork.",
        "com.apple.MainStage", "com.apple.Playgrounds",
      ]
      if !downloadable.contains(where: { app.bundleID.hasPrefix($0) }) { return "system" }
    }
    return nil
  }
  private func validate(_ app: InstalledApp) throws -> URL {
    guard Self.protection(app) == nil else {
      throw OperationError("This application is protected.")
    }
    let url = URL(fileURLWithPath: app.path).standardizedFileURL
    guard url.path == app.path, url.pathExtension.lowercased() == "app",
      !app.path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
      roots.contains(where: { root in
        let root = root.standardizedFileURL
        let relative = String(url.path.dropFirst(root.path.count + 1))
        return url.path.hasPrefix(root.path + "/")
          && !relative.split(separator: "/").dropLast().contains(where: {
            $0.lowercased().hasSuffix(".app")
          })
      }), url.resolvingSymlinksInPath().path == url.path,
      let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
      info["CFBundleIdentifier"] as? String == app.bundleID
    else {
      throw OperationError(
        "The selected app's location or identity changed. Refresh and review again.")
    }
    let infoURL = url.appendingPathComponent("Contents/Info.plist")
    guard infoURL.resolvingSymlinksInPath().path == infoURL.path else {
      throw OperationError("The app's identity file is a symbolic link.")
    }
    return url
  }
  private func fingerprint(_ url: URL) throws -> String {
    let fm = FileManager.default
    var data = Data()
    for item in [
      url, url.deletingLastPathComponent(), url.appendingPathComponent("Contents/Info.plist"),
    ] {
      let a = try fm.attributesOfItem(atPath: item.path)
      // Parent mtime is deliberately excluded: another queue entry may share that parent.
      if item != url.deletingLastPathComponent() {
        data.append(Data("\(a[.modificationDate] ?? "")|\(a[.size] ?? "")".utf8))
      }
      data.append(Data("\(item.path)|\(a[.systemNumber] ?? "")|\(a[.systemFileNumber] ?? "")".utf8))
    }
    data.append(try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")))
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  private func caskMetadata(_ token: String, app: InstalledApp) throws -> String {
    guard brew.available, CaskIndex.validToken(token) else {
      throw OperationError("Homebrew is unavailable.")
    }
    let listing = try Command.run(brew.executable, ["list", "--cask", token], timeout: 30)
    guard listing.code == 0,
      listing.output.split(separator: "\n").contains(where: {
        URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces))
          .resolvingSymlinksInPath().path == app.path
      })
    else { throw OperationError("Homebrew ownership could not be confirmed.") }
    // Homebrew uninstalls the recorded cask, which may differ from today's API entry.
    // Read the same timestamped metadata and receipt; never approve only the current remote definition.
    let fm = FileManager.default
    guard
      let directory = caskRooms.map({ $0.appendingPathComponent(token) }).first(where: {
        fm.fileExists(atPath: $0.appendingPathComponent(".metadata/INSTALL_RECEIPT.json").path)
      })
    else { throw OperationError("Homebrew's installed receipt is missing.") }
    func read(_ url: URL) throws -> Data {
      guard url.resolvingSymlinksInPath().path == url.path,
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 4_000_000
      else {
        throw OperationError("Homebrew's installed metadata is unreadable or unsafe.")
      }
      return try Data(contentsOf: url)
    }
    let receiptData = try read(directory.appendingPathComponent(".metadata/INSTALL_RECEIPT.json"))
    guard let receipt = try JSONSerialization.jsonObject(with: receiptData) as? [String: Any],
      receipt["uninstall_flight_blocks"] as? Bool != true
    else {
      throw OperationError(
        "This Homebrew app uses uninstall scripts that require a dedicated review.")
    }
    let metadata = directory.appendingPathComponent(".metadata")
    let versions = try fm.contentsOfDirectory(
      at: metadata, includingPropertiesForKeys: [.isDirectoryKey])
    var timestamps: [URL] = []
    for version in versions
    where (try? version.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
      timestamps += try fm.contentsOfDirectory(
        at: version, includingPropertiesForKeys: [.isDirectoryKey]
      ).filter {
        (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
      }
    }
    guard let latest = timestamps.max(by: { $0.lastPathComponent < $1.lastPathComponent }) else {
      throw OperationError("Homebrew's installed cask definition is missing.")
    }
    let recordedURL = latest.appendingPathComponent("Casks/" + token + ".json")
    let recordedData = try read(recordedURL)
    guard let recorded = try JSONSerialization.jsonObject(with: recordedData) as? [String: Any],
      let artifacts = (recorded["artifacts"] ?? receipt["uninstall_artifacts"]) as? [[String: Any]],
      !artifacts.isEmpty
    else {
      throw OperationError("Homebrew's recorded uninstall instructions are incomplete.")
    }
    // Never execute a zap or unreviewed script/delete/pkgutil hook behind a bundle-only review.
    let allowed: Set<String> = ["app", "binary", "command_wrapper", "uninstall", "zap"]
    guard artifacts.allSatisfy({ Set($0.keys).isSubset(of: allowed) }) else {
      throw OperationError(
        "This Homebrew app includes package or script actions. A dedicated uninstall handler is required."
      )
    }
    for artifact in artifacts {
      if let actions = artifact["uninstall"] as? [[String: Any]],
        !actions.allSatisfy({ Set($0.keys).isSubset(of: ["quit", "login_item"]) })
      {
        throw OperationError(
          "This Homebrew uninstaller changes services or external files. Those actions need a dedicated review."
        )
      }
    }
    // A cask can own multiple app bundles. Removing one must not silently remove the others.
    let appArtifacts = artifacts.compactMap { $0["app"] as? [Any] }
    guard appArtifacts.count == 1 else {
      throw OperationError("This cask owns several app bundles. Review the whole package first.")
    }
    var reviewed = receiptData + recordedData
    let config = directory.appendingPathComponent(".metadata/config.json")
    if fm.fileExists(atPath: config.path) { reviewed.append(try read(config)) }
    return SHA256.hash(data: reviewed).map { String(format: "%02x", $0) }.joined()
  }
  public func prepare(_ identity: RemovalIdentity) throws -> RemovalPlan {
    let url = try validate(identity.app)
    let fm = FileManager.default
    for relative in ["Contents/Library/SystemExtensions", "Contents/Library/Extensions"] {
      if let children = try? fm.contentsOfDirectory(
        atPath: url.appendingPathComponent(relative).path), !children.isEmpty
      {
        throw OperationError(
          "This app includes system extensions. Its supported uninstaller must deactivate them first."
        )
      }
    }
    let index = CaskIndex(rooms: caskRooms)
    guard index.warnings.isEmpty else {
      throw OperationError(index.warnings.joined(separator: "\n"))
    }
    let tokens = index.owners[url.path] ?? []
    guard tokens.count <= 1 else {
      throw OperationError("More than one cask claims this app. Resolve Homebrew ownership first.")
    }
    let token = tokens.first
    let metadata = try token.map { try caskMetadata($0, app: identity.app) }
    return RemovalPlan(
      identity: identity, method: token == nil ? .trash : .homebrew,
      cask: token, fingerprint: try fingerprint(url), caskFingerprint: metadata)
  }
  public func remove(
    _ plan: RemovalPlan, onStage: (QueueStage) -> Void,
    log: @escaping (String) -> Void = { _ in }
  ) throws -> RemovalResult {
    onStage(.preparing)
    let app = plan.identity.app
    let url = try validate(app)
    guard try fingerprint(url) == plan.fingerprint else {
      throw OperationError("The app changed after review. Create a fresh removal plan.")
    }
    guard NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    else {
      throw OperationError("Quit this app before removing it. Unsaved work has been preserved.")
    }
    let current = try prepare(plan.identity)
    guard current.method == plan.method, current.cask == plan.cask,
      current.caskFingerprint == plan.caskFingerprint
    else {
      throw OperationError("The removal method changed after review. Review again.")
    }
    // Repeat identity immediately before the mutation, after all potentially slow probes.
    guard try fingerprint(url) == plan.fingerprint else {
      throw OperationError("The app changed during preparation.")
    }
    onStage(.removing)
    var trashPath: String?
    if let token = plan.cask {
      let result = try Command.run(brew.executable, ["uninstall", "--cask", token], onOutput: log)
      guard result.code == 0 else {
        throw OperationError(
          "Homebrew did not complete removal. Inspect the log; no fallback deletion was attempted.")
      }
      let remaining = try Command.run(
        brew.executable, ["list", "--cask", "--versions"], timeout: 30)
      guard remaining.code == 0,
        !remaining.output.split(separator: "\n").contains(where: {
          $0.split(separator: " ").first == Substring(token)
        })
      else {
        throw OperationError(
          "Homebrew still records this cask, or its state could not be verified.")
      }
    } else {
      var destination: NSURL?
      try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
      guard let trash = destination as URL?,
        let info = NSDictionary(contentsOf: trash.appendingPathComponent("Contents/Info.plist")),
        info["CFBundleIdentifier"] as? String == app.bundleID
      else {
        throw OperationError("The app's destination in Trash could not be verified.")
      }
      trashPath = trash.path
    }
    onStage(.verifying)
    guard !FileManager.default.fileExists(atPath: url.path),
      (try? FileManager.default.attributesOfItem(atPath: url.path)) == nil
    else {
      throw OperationError("The app is still present at the selected location.")
    }
    let inventory = Inventory.scan(roots: roots)
    guard inventory.warnings.isEmpty else {
      throw OperationError(
        "The app was moved, but inventory verification is incomplete. Refresh to inspect the result."
      )
    }
    return RemovalResult(
      trashPath: trashPath,
      remainingCopies: inventory.apps.filter { $0.bundleID == app.bundleID }.count)
  }
}
