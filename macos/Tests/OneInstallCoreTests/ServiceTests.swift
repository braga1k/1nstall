import Foundation
import OneInstallCore

extension CoreTests {
  func serviceFixture(loaded: Bool = false, system: Bool = false) throws -> (
    RemovalIdentity, ServiceRemoval, URL
  ) {
    let installed = try removalFixture()
    let executable = URL(fileURLWithPath: installed.path).appendingPathComponent(
      "Contents/MacOS/fixture-sleep")
    try FileManager.default.createDirectory(
      at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: executable)
    let folder = root.appendingPathComponent(
      system ? "SystemLibrary/LaunchDaemons" : "Library/LaunchAgents")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let label = "test.braga1k.1nstall.fixture." + UUID().uuidString
    let url = folder.appendingPathComponent(label + ".plist")
    let contents: [String: Any] = [
      "Label": label, "ProgramArguments": [executable.path, "120"], "RunAtLoad": true,
    ]
    try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0).write(
      to: url)
    if loaded {
      let result = try Command.run(
        "/bin/launchctl", ["bootstrap", "gui/\(getuid())", url.path], timeout: 10)
      guard result.code == 0 else { throw CheckError(description: result.output) }
    }
    return (
      RemovalIdentity(app: installed),
      ServiceRemoval(home: root, systemLibrary: root.appendingPathComponent("SystemLibrary")), url
    )
  }
  func testServiceDiscoveryBindsExecutableAndProtectsForeignLabels() throws {
    let (identity, planner, url) = try serviceFixture()
    let services = try planner.discover(identity)
    expectEqual(services.count, 1)
    expectFalse(services[0].loaded)
    expectFalse(services[0].privileged)
    let content = try PropertyListSerialization.data(
      fromPropertyList: ["Label": "com.apple.fixture", "Program": services[0].program],
      format: .xml, options: 0)
    try content.write(to: url)
    expectTrue(try planner.discover(identity).isEmpty)
    expectError(try planner.validate(services[0], identity: identity))
    try PropertyListSerialization.data(
      fromPropertyList: [
        "Label": "test.braga1k.foreign", "Program": "/Applications/Other.app/helper",
      ], format: .xml, options: 0
    ).write(to: url)
    expectTrue(try planner.discover(identity).isEmpty)
  }
  func testSystemServicesAreReviewedButNeverStoppedWithoutAuthorisation() throws {
    let (identity, planner, _) = try serviceFixture(system: true)
    let services = try planner.discover(identity, probe: false)
    expectEqual(services.count, 1)
    expectTrue(services[0].privileged)
    expectEqual(services[0].domain, "system")
    let request = AdministrativeRequest(
      action: .stopServices, identity: identity, services: services)
    expectError(try AdministrativeRemoval.execute(request))
    expectTrue(FileManager.default.fileExists(atPath: identity.app.path))
  }
  func testLoadedDisposableServiceStopsBeforeAppRemoval() throws {
    let (identity, planner, plist) = try serviceFixture(loaded: true)
    let label = try requireValue(NSDictionary(contentsOf: plist)?["Label"] as? String)
    defer {
      _ = try? Command.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"], timeout: 10)
    }
    let engine = RemovalEngine(
      roots: [root.appendingPathComponent("Applications")], caskRooms: [], services: planner)
    let plan = try engine.prepare(identity)
    expectEqual(plan.services.count, 1)
    expectTrue(plan.services[0].loaded)
    var stages: [QueueStage] = []
    let result = try engine.remove(plan, onStage: { stages.append($0) })
    let trash = URL(fileURLWithPath: try requireValue(result.trashPath))
    defer {
      try? FileManager.default.moveItem(at: trash, to: URL(fileURLWithPath: identity.app.path))
    }
    expectEqual(stages, [.preparing, .stoppingServices, .removing, .verifying])
    expectEqual(
      try Command.run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"], timeout: 10).code,
      113)
    expectTrue(
      FileManager.default.fileExists(atPath: plist.path), "Plist stays for separate data review")
  }
  func testChangedServicePlanPreservesAppAndService() throws {
    let (identity, planner, plist) = try serviceFixture()
    let engine = RemovalEngine(
      roots: [root.appendingPathComponent("Applications")], caskRooms: [], services: planner)
    let plan = try engine.prepare(identity)
    try PropertyListSerialization.data(
      fromPropertyList: ["Label": "test.braga1k.changed", "Program": "/usr/bin/true"], format: .xml,
      options: 0
    ).write(to: plist)
    expectError(try engine.remove(plan, onStage: { _ in }))
    expectTrue(FileManager.default.fileExists(atPath: identity.app.path))
  }
  func testServiceSiblingCopyPreservesTheSharedJob() throws {
    let (identity, planner, _) = try serviceFixture()
    let engine = RemovalEngine(
      roots: [root.appendingPathComponent("Applications")], caskRooms: [], services: planner)
    let plan = try engine.prepare(identity)
    try bundle("Applications/Another.app", id: identity.bundleID)
    expectError(try engine.remove(plan, onStage: { _ in }))
    expectTrue(FileManager.default.fileExists(atPath: identity.app.path))
  }
  func testAdministrativeWorkerRejectsUnprivilegedMalformedAndProtectedRequests() throws {
    let app = InstalledApp(
      name: "Protected", bundleID: "com.apple.finder", path: "/System/Applications/Finder.app",
      version: "1", store: false)
    let request = AdministrativeRequest(action: .trashApp, identity: RemovalIdentity(app: app))
    expectError(try AdministrativeRemoval.validate(request))
    expectError(try AdministrativeRemoval.execute(request))
    let installed = try removalFixture()
    // Even a valid fixture outside production roots cannot be submitted to the production worker.
    let outside = AdministrativeRequest(
      action: .trashApp, identity: RemovalIdentity(app: installed))
    expectError(try AdministrativeRemoval.validate(outside))
    expectError(try AdministrativeRemoval.home(for: 0))
    expectTrue(FileManager.default.fileExists(atPath: installed.path))
  }
}
