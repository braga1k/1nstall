import Foundation
import OneInstallCore

extension CoreTests {
  func testRecoveryJournalRequiresAnExistingMatchingBundle() throws {
    let app = try removalFixture()
    let identity = RemovalIdentity(app: app)
    let recovery = AdministrativeRemoval.recoveryDirectory(home: root)
    try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
    let destination = recovery.appendingPathComponent("Recovered.app")
    let request = AdministrativeRequest(action: .trashApp, identity: identity)
    let record = RecoveryRecord(
      request: request, source: URL(fileURLWithPath: app.path), destination: destination)
    try JSONEncoder().encode(record).write(
      to: recovery.appendingPathComponent(request.nonce.uuidString + ".json"))
    expectTrue(
      RecoveryStore.records(home: root).isEmpty, "Prepared journal is not proof of a completed move"
    )
    try FileManager.default.moveItem(at: URL(fileURLWithPath: app.path), to: destination)
    expectEqual(RecoveryStore.records(home: root).map(\.recoveryPath), [destination.path])
    let other = ["CFBundleIdentifier": "test.other.application"]
    try PropertyListSerialization.data(fromPropertyList: other, format: .xml, options: 0).write(
      to: destination.appendingPathComponent("Contents/Info.plist"))
    expectTrue(
      RecoveryStore.records(home: root).isEmpty, "Replaced bundle must not be offered for recovery")
  }
  func testRecoveryJournalCannotPointOutsideRecoveryDirectory() throws {
    let app = try removalFixture()
    let recovery = AdministrativeRemoval.recoveryDirectory(home: root)
    try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
    let request = AdministrativeRequest(action: .trashApp, identity: RemovalIdentity(app: app))
    let record = RecoveryRecord(
      request: request, source: URL(fileURLWithPath: app.path),
      destination: URL(fileURLWithPath: app.path))
    try JSONEncoder().encode(record).write(
      to: recovery.appendingPathComponent(request.nonce.uuidString + ".json"))
    expectTrue(RecoveryStore.records(home: root).isEmpty)
  }
  func testRecoveryRefusesExistingDestinationBeforeAuthorisation() throws {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser
    let recovery = AdministrativeRemoval.recoveryDirectory(home: home)
    try fm.createDirectory(
      at: recovery, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let name = "1nstall Recovery Test " + UUID().uuidString + ".app"
    let source = recovery.appendingPathComponent(name)
    let target = home.appendingPathComponent("Applications").appendingPathComponent(name)
    defer {
      try? fm.removeItem(at: source)
      try? fm.removeItem(at: target)
    }
    let fixture = try removalFixture()
    try fm.copyItem(at: URL(fileURLWithPath: fixture.path), to: source)
    try fm.copyItem(at: URL(fileURLWithPath: fixture.path), to: target)
    let identity = RemovalIdentity(
      app: InstalledApp(
        name: name, bundleID: fixture.bundleID, path: target.path, version: "1", store: false))
    var authorised = false
    expectError(
      try RemovalEngine().restore(
        identity, from: source.path,
        authorise: { _ in
          authorised = true
          throw OperationError("Must not request authorisation")
        }))
    expectFalse(authorised)
    expectTrue(fm.fileExists(atPath: source.path))
    expectTrue(fm.fileExists(atPath: target.path))
    try fm.removeItem(at: target)
    expectError(
      try RemovalEngine().restore(
        identity, from: source.path,
        authorise: { _ in
          authorised = true
          throw OperationError("Simulated cancellation before mutation")
        }))
    expectTrue(authorised, "Valid recovery reaches the authorisation boundary")
    expectTrue(fm.fileExists(atPath: source.path))
    expectFalse(fm.fileExists(atPath: target.path))
  }
  func testNewQueueStagesAndRecoveryPathSurviveRestart() throws {
    let app = try removalFixture()
    var entry = QueueEntry(plan: try removalEngine.prepare(RemovalIdentity(app: app)))
    entry.stage = .authorising
    entry.recoveryPath = "/fixture/recovery.app"
    var state = SavedState()
    state.queue = [entry]
    let path = root.appendingPathComponent("state.json")
    try Persistence.save(state, to: path)
    let read = try Persistence.read(path)
    expectEqual(read.queue[0].stage, .interrupted)
    expectEqual(read.queue[0].recoveryPath, entry.recoveryPath)
  }
}
