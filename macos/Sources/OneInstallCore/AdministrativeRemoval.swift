import AppKit
import Darwin
import Foundation
import Security

public struct AdministrativeRequest: Codable, Sendable {
  public enum Action: String, Codable, Sendable {
    case stopServices, trashApp, trashData, restoreApp
  }
  public let action: Action
  public let identity: RemovalIdentity
  public let appFingerprint: String?
  public let services: [AssociatedService]
  public let data: Leftover?
  public let recoveryPath: String?
  public let uid: UInt32
  public let nonce: UUID
  public init(
    action: Action, identity: RemovalIdentity, appFingerprint: String? = nil,
    services: [AssociatedService] = [], data: Leftover? = nil, recoveryPath: String? = nil,
    uid: UInt32 = getuid()
  ) {
    self.action = action
    self.identity = identity
    self.appFingerprint = appFingerprint
    self.services = services
    self.data = data
    self.recoveryPath = recoveryPath
    self.uid = uid
    self.nonce = UUID()
  }
}
public struct AdministrativeResult: Codable, Sendable {
  public let nonce: UUID
  public let destination: String?
  public let stopped: [String]
}

/// A one-shot worker. No caller-supplied commands, permission changes on existing files, permanent service or delete API.
/// Every request is separately authorised by macOS before this executable starts as root.
public enum AdministrativeRemoval {
  public static func recoveryDirectory(home: URL) -> URL {
    home.appendingPathComponent("Library/Application Support/1nstall-mac-preview/Recovery")
  }
  public static func home(for uid: UInt32) throws -> URL {
    guard uid >= 501, let entry = getpwuid(uid), let directory = entry.pointee.pw_dir else {
      throw OperationError("The account for this removal could not be verified.")
    }
    let home = URL(fileURLWithPath: String(cString: directory)).standardizedFileURL
    guard home.path.hasPrefix("/Users/"), home.pathComponents.count == 3,
      home.resolvingSymlinksInPath().path == home.path
    else {
      throw OperationError("The account's home directory could not be verified.")
    }
    return home
  }
  public static func validate(_ request: AdministrativeRequest) throws -> URL {
    let home = try home(for: request.uid)
    guard RemovalEngine.protection(request.identity.app) == nil,
      request.identity.bundleID != "com.braga1k.1nstall.mac.preview",
      request.identity.bundleID.range(
        of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil
    else {
      throw OperationError("This application is protected.")
    }
    guard
      NSRunningApplication.runningApplications(withBundleIdentifier: request.identity.bundleID)
        .isEmpty
    else {
      throw OperationError("Quit this app before removing it. Unsaved work has been preserved.")
    }
    let engine = RemovalEngine(roots: [
      URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications"),
    ])
    switch request.action {
    case .restoreApp:
      guard let path = request.recoveryPath, request.data == nil, request.services.isEmpty else {
        throw OperationError("Invalid recovery request.")
      }
      let source = URL(fileURLWithPath: path)
      let target = URL(fileURLWithPath: request.identity.app.path)
      let recovery = recoveryDirectory(home: home)
      guard source.deletingLastPathComponent() == recovery, source.pathExtension == "app",
        source.standardizedFileURL.path == source.path,
        source.resolvingSymlinksInPath().path == source.path,
        target.standardizedFileURL.path == target.path,
        target.resolvingSymlinksInPath().path == target.path,
        target.pathExtension == "app",
        engine.roots.contains(where: { target.path.hasPrefix($0.path + "/") }),
        !target.pathComponents.dropLast().contains(where: { $0.lowercased().hasSuffix(".app") }),
        (try? FileManager.default.attributesOfItem(atPath: target.path)) == nil,
        NSDictionary(contentsOf: source.appendingPathComponent("Contents/Info.plist"))?[
          "CFBundleIdentifier"] as? String == request.identity.bundleID,
        request.appFingerprint == (try engine.fingerprint(source))
      else {
        throw OperationError(
          "The recovery item or destination changed. Existing files were preserved.")
      }
    case .stopServices, .trashApp:
      let url = try engine.validate(request.identity.app)
      guard request.appFingerprint == (try engine.fingerprint(url)) else {
        throw OperationError("The app changed after review. Create a fresh removal plan.")
      }
      guard request.data == nil else { throw OperationError("Invalid administrative request.") }
      if request.action == .trashApp {
        let index = CaskIndex()
        guard index.warnings.isEmpty, (index.owners[url.path] ?? []).isEmpty,
          request.services.isEmpty
        else { throw OperationError("Homebrew or services require their reviewed removal method.") }
      } else {
        guard !request.services.isEmpty, request.services.count <= 64 else {
          throw OperationError("Invalid service plan.")
        }
        let planner = ServiceRemoval(home: home, uid: request.uid)
        for service in request.services {
          guard service.privileged, service.domain == "system" else {
            throw OperationError("Invalid service scope.")
          }
          try planner.validate(service, identity: request.identity)
        }
      }
    case .trashData:
      guard let item = request.data, request.services.isEmpty, item.kind == .system,
        item.reason == "systemExact", item.selectable
      else { throw OperationError("Protected, shared or unreviewed path.") }
      let inventory = Inventory.scan(roots: engine.roots)
      guard inventory.warnings.isEmpty,
        !inventory.apps.contains(where: { $0.bundleID == request.identity.bundleID }),
        !FileManager.default.fileExists(atPath: request.identity.app.path)
      else {
        throw OperationError("An installed or running copy still uses these data.")
      }
      let current = LeftoverScanner(home: home).scan(request.identity, installed: inventory.apps)
      guard
        current.items.contains(where: {
          $0.id == item.id && $0.fingerprint == item.fingerprint && $0.selectable
            && $0.kind == .system && $0.reason == "systemExact"
        })
      else {
        throw OperationError("Files changed after review. Scan again.")
      }
    }
    return home
  }
  public static func execute(_ request: AdministrativeRequest) throws -> AdministrativeResult {
    guard geteuid() == 0 else { throw OperationError("Administrator authorisation is required.") }
    let home = try validate(request)
    switch request.action {
    case .restoreApp:
      let source = URL(fileURLWithPath: request.recoveryPath!)
      let target = URL(fileURLWithPath: request.identity.app.path)
      let destination = try moveToDirectory(
        source, directory: target.deletingLastPathComponent(), uid: nil,
        name: target.lastPathComponent, beforeMove: { _ = try validate(request) })
      return AdministrativeResult(nonce: request.nonce, destination: destination.path, stopped: [])
    case .stopServices:
      let planner = ServiceRemoval(home: home, uid: request.uid)
      var stopped: [String] = []
      for service in request.services {
        _ = try validate(request)
        try planner.stop(service, identity: request.identity)
        stopped.append(service.id)
      }
      return AdministrativeResult(nonce: request.nonce, destination: nil, stopped: stopped)
    case .trashApp, .trashData:
      let source =
        request.action == .trashApp
        ? URL(fileURLWithPath: request.identity.app.path) : request.data!.url
      // A root process cannot assume access to the user's TCC-protected Trash.
      // Use the app's user-owned recovery directory; never accept an arbitrary destination.
      let recovery = recoveryDirectory(home: home)
      let suffix = source.pathExtension.isEmpty ? "" : "." + String(source.pathExtension.prefix(16))
      let name = "1nstall-" + request.nonce.uuidString + suffix
      let planned = recovery.appendingPathComponent(name)
      try RecoveryStore.write(
        RecoveryRecord(request: request, source: source, destination: planned), root: recovery,
        uid: request.uid)
      let destination = try moveToDirectory(
        source, directory: recovery, uid: request.uid, name: name,
        beforeMove: { _ = try validate(request) })
      return AdministrativeResult(nonce: request.nonce, destination: destination.path, stopped: [])
    }
  }
  static func moveToDirectory(
    _ source: URL, directory trash: URL, uid: UInt32?, name: String? = nil,
    beforeMove: () throws -> Void
  ) throws -> URL {
    guard source.resolvingSymlinksInPath().path == source.path,
      trash.resolvingSymlinksInPath().path == trash.path
    else { throw OperationError("Protected link.") }
    let sourceFD = open(
      source.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard sourceFD >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { close(sourceFD) }
    let trashFD = open(trash.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard trashFD >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { close(trashFD) }
    var sourceInfo = stat()
    var trashInfo = stat()
    guard fstatat(sourceFD, source.lastPathComponent, &sourceInfo, AT_SYMLINK_NOFOLLOW) == 0,
      fstat(trashFD, &trashInfo) == 0, uid == nil || trashInfo.st_uid == uid!,
      trashInfo.st_mode & 0o002 == 0
    else { throw OperationError("The recovery destination could not be verified.") }
    try beforeMove()
    var rechecked = stat()
    guard fstatat(sourceFD, source.lastPathComponent, &rechecked, AT_SYMLINK_NOFOLLOW) == 0,
      rechecked.st_ino == sourceInfo.st_ino, rechecked.st_dev == sourceInfo.st_dev
    else {
      throw OperationError("The reviewed file changed before removal.")
    }
    let name =
      name ?? source.deletingPathExtension().lastPathComponent + " · 1nstall " + UUID().uuidString
      + (source.pathExtension.isEmpty ? "" : "." + source.pathExtension)
    guard renameatx_np(sourceFD, source.lastPathComponent, trashFD, name, UInt32(RENAME_EXCL)) == 0
    else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    var moved = stat()
    guard fstatat(trashFD, name, &moved, AT_SYMLINK_NOFOLLOW) == 0,
      moved.st_ino == sourceInfo.st_ino, moved.st_dev == sourceInfo.st_dev,
      fstatat(sourceFD, source.lastPathComponent, &rechecked, AT_SYMLINK_NOFOLLOW) != 0,
      errno == ENOENT
    else {
      throw OperationError("Moving to Trash was not confirmed.")
    }
    return trash.appendingPathComponent(name)
  }
}

public enum NativeAuthorisation {
  /// Called off the main thread. No password is read by the application or written to logs.
  public static func perform(_ request: AdministrativeRequest) throws -> AdministrativeResult {
    guard !Thread.isMainThread else {
      throw OperationError("Authorisation must not block the interface.")
    }
    let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/1nstall-admin")
    guard FileManager.default.isExecutableFile(atPath: helper.path),
      helper.resolvingSymlinksInPath().path == helper.path
    else { throw OperationError("The administrative component is missing.") }
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
      let code,
      SecStaticCodeCheckValidity(
        code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode), nil)
        == errSecSuccess
    else {
      throw OperationError("The app signature is invalid. Rebuild before requesting authorisation.")
    }
    if request.action == .trashApp || request.action == .trashData {
      let recovery = AdministrativeRemoval.recoveryDirectory(
        home: try AdministrativeRemoval.home(for: request.uid))
      try FileManager.default.createDirectory(
        at: recovery, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      guard recovery.resolvingSymlinksInPath().path == recovery.path else {
        throw OperationError("The recovery directory is a symbolic link.")
      }
    }
    let data = try JSONEncoder().encode(request)
    guard data.count < 128_000 else {
      throw OperationError("The administrative request is too large.")
    }
    // Both escaping layers are required: POSIX arguments first, AppleScript string second.
    func shell(_ value: String) -> String {
      "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    let command = shell(helper.path) + " " + shell(data.base64EncodedString())
    let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
      of: "\"", with: "\\\"")
    let source = "do shell script \"" + literal + "\" with administrator privileges"
    var error: NSDictionary?
    guard let script = NSAppleScript(source: source) else {
      throw OperationError("Unable to prepare native authorisation.")
    }
    let response = script.executeAndReturnError(&error)
    if let error {
      if error[NSAppleScript.errorNumber] as? Int == -128 {
        throw OperationError("Administrator authorisation was cancelled. No success was recorded.")
      }
      throw OperationError(
        "macOS authorisation (\(error[NSAppleScript.errorNumber] ?? "unknown")): "
          + (error[NSAppleScript.errorMessage] as? String ?? "Administrative removal failed."))
    }
    guard let text = response.stringValue, let output = text.data(using: .utf8),
      let result = try? JSONDecoder().decode(AdministrativeResult.self, from: output),
      result.nonce == request.nonce
    else {
      throw OperationError("The administrative result could not be verified.")
    }
    return result
  }
}
