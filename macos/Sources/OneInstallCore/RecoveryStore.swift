import Foundation

public struct RecoveryRecord: Codable, Identifiable, Sendable {
  public let id: UUID
  public let identity: RemovalIdentity
  public let originalPath: String
  public let recoveryPath: String
  public let date: Date
  public let application: Bool
  public init(request: AdministrativeRequest, source: URL, destination: URL) {
    id = request.nonce
    identity = request.identity
    originalPath = source.path
    recoveryPath = destination.path
    date = Date()
    application = request.action == .trashApp
  }
}

public enum RecoveryStore {
  /// Records are created before the move. Presence and identity, never the journal alone,
  /// determine whether something remains available to restore after an interruption.
  public static func records(home: URL = FileManager.default.homeDirectoryForCurrentUser)
    -> [RecoveryRecord]
  {
    let root = AdministrativeRemoval.recoveryDirectory(home: home)
    guard root.resolvingSymlinksInPath().path == root.path,
      let files = try? FileManager.default.contentsOfDirectory(
        at: root, includingPropertiesForKeys: [.fileSizeKey])
    else { return [] }
    return files.filter { $0.pathExtension == "json" }.compactMap { url in
      guard url.resolvingSymlinksInPath().path == url.path,
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 128_000,
        let data = try? Data(contentsOf: url),
        let record = try? JSONDecoder().decode(RecoveryRecord.self, from: data),
        url.lastPathComponent == record.id.uuidString + ".json"
      else { return nil }
      let recovered = URL(fileURLWithPath: record.recoveryPath)
      guard recovered.deletingLastPathComponent() == root,
        recovered.standardizedFileURL.path == recovered.path,
        recovered.resolvingSymlinksInPath().path == recovered.path,
        FileManager.default.fileExists(atPath: recovered.path)
      else { return nil }
      if record.application {
        guard
          NSDictionary(contentsOf: recovered.appendingPathComponent("Contents/Info.plist"))?[
            "CFBundleIdentifier"] as? String == record.identity.bundleID,
          record.originalPath == record.identity.app.path
        else { return nil }
      }
      return record
    }.sorted { $0.date > $1.date }
  }
  static func write(_ record: RecoveryRecord, root: URL, uid: UInt32) throws {
    let url = root.appendingPathComponent(record.id.uuidString + ".json")
    guard root.resolvingSymlinksInPath().path == root.path,
      (try FileManager.default.attributesOfItem(atPath: root.path)[.ownerAccountID] as? NSNumber)?
        .uint32Value == uid
    else {
      throw OperationError("The recovery destination could not be verified.")
    }
    try JSONEncoder().encode(record).write(to: url, options: .withoutOverwriting)
    // Ownership is set only on this newly created journal, never on an existing app or data.
    try FileManager.default.setAttributes(
      [.ownerAccountID: uid, .posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}
