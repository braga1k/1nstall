import Foundation
import OneInstallCore

extension CoreTests {
  func removalFixture(_ path: String = "Applications/Uncatalogued.app", store: Bool = false) throws
    -> InstalledApp
  {
    try bundle(path, id: "test.onenstall.disposable")
    if store {
      try file(path + "/Contents/_MASReceipt/receipt", "fixture; not a genuine store receipt")
    }
    return try requireValue(
      Inventory.scan(roots: [root.appendingPathComponent("Applications")]).apps.first {
        $0.path == root.appendingPathComponent(path).path
      })
  }
  var removalEngine: RemovalEngine {
    RemovalEngine(roots: [root.appendingPathComponent("Applications")], caskRooms: [])
  }
  func testNativeRemovalOutsideCatalogAndRestore() throws {
    let installed = try removalFixture()
    let identity = RemovalIdentity(app: installed)
    let plan = try removalEngine.prepare(identity)
    expectEqual(plan.method, .trash)
    var stages: [QueueStage] = []
    let result = try removalEngine.remove(plan, onStage: { stages.append($0) })
    let trash = URL(fileURLWithPath: try requireValue(result.trashPath))
    defer { try? FileManager.default.moveItem(at: trash, to: URL(fileURLWithPath: installed.path)) }
    expectEqual(stages, [.preparing, .removing, .verifying])
    expectEqual(result.remainingCopies, 0)
    expectFalse(FileManager.default.fileExists(atPath: installed.path))
    expectEqual(
      NSDictionary(contentsOf: trash.appendingPathComponent("Contents/Info.plist"))?[
        "CFBundleIdentifier"] as? String, installed.bundleID)
  }
  func testStoreReceiptDoesNotForceGuidedRemoval() throws {
    let installed = try removalFixture(store: true)
    expectTrue(installed.store)
    let plan = try removalEngine.prepare(RemovalIdentity(app: installed))
    expectEqual(plan.method, .trash)
    let result = try removalEngine.remove(plan, onStage: { _ in })
    let trash = URL(fileURLWithPath: try requireValue(result.trashPath))
    defer { try? FileManager.default.moveItem(at: trash, to: URL(fileURLWithPath: installed.path)) }
    expectTrue(
      FileManager.default.fileExists(
        atPath: trash.appendingPathComponent("Contents/_MASReceipt/receipt").path))
  }
  func testRemovalOnlyAffectsSelectedCopy() throws {
    let installed = try removalFixture()
    try bundle("Applications/Another.app", id: installed.bundleID)
    try file("Library/Preferences/\(installed.bundleID).plist")
    let identity = RemovalIdentity(app: installed)
    let scanner = LeftoverScanner(home: root)
    let data = try requireValue(scanner.scan(identity).items.first)
    let result = try removalEngine.remove(try removalEngine.prepare(identity), onStage: { _ in })
    let trash = URL(fileURLWithPath: try requireValue(result.trashPath))
    defer { try? FileManager.default.moveItem(at: trash, to: URL(fileURLWithPath: installed.path)) }
    expectEqual(result.remainingCopies, 1)
    let remaining = Inventory.scan(roots: [root.appendingPathComponent("Applications")]).apps
    expectError(try scanner.trash(data, for: identity, installed: remaining))
    expectTrue(
      FileManager.default.fileExists(
        atPath: root.appendingPathComponent("Applications/Another.app").path))
  }
  func testChangedIdentityInvalidatesRemovalPlan() throws {
    let installed = try removalFixture()
    let plan = try removalEngine.prepare(RemovalIdentity(app: installed))
    let original = URL(fileURLWithPath: installed.path)
    let renamed = root.appendingPathComponent("Applications/Preserved.app")
    try FileManager.default.moveItem(at: original, to: renamed)
    try bundle("Applications/Uncatalogued.app", id: installed.bundleID)
    expectError(try removalEngine.remove(plan, onStage: { _ in }))
    expectTrue(FileManager.default.fileExists(atPath: original.path))
    expectTrue(FileManager.default.fileExists(atPath: renamed.path))
  }
  func testRemovalRejectsSymlinksNestedAppsAndSystem() throws {
    let installed = try removalFixture()
    let link = root.appendingPathComponent("Applications/Alias.app")
    try FileManager.default.createSymbolicLink(
      at: link, withDestinationURL: URL(fileURLWithPath: installed.path))
    let alias = InstalledApp(
      name: installed.name, bundleID: installed.bundleID, path: link.path, version: "1",
      store: false)
    expectError(try removalEngine.prepare(RemovalIdentity(app: alias)))
    try bundle("Applications/Uncatalogued.app/Contents/Helper.app", id: installed.bundleID)
    let embedded = InstalledApp(
      name: "Helper", bundleID: installed.bundleID, path: installed.path + "/Contents/Helper.app",
      version: "1", store: false)
    expectError(try removalEngine.prepare(RemovalIdentity(app: embedded)))
    let protected = InstalledApp(
      name: "System", bundleID: "com.apple.finder",
      path: root.appendingPathComponent("Applications/System.app").path, version: "1", store: false)
    expectEqual(RemovalEngine.protection(protected), "system")
    let appleStore = InstalledApp(
      name: "Logic Pro", bundleID: "com.apple.logic10", path: "/Applications/Logic Pro.app",
      version: "1", store: true)
    expectEqual(RemovalEngine.protection(appleStore), nil)
    let outside = RemovalEngine(roots: [root.appendingPathComponent("Elsewhere")], caskRooms: [])
    expectError(try outside.prepare(RemovalIdentity(app: installed)))
  }
  func testSystemExtensionsRequireARealUninstaller() throws {
    let installed = try removalFixture()
    try file(
      "Applications/Uncatalogued.app/Contents/Library/SystemExtensions/Driver.systemextension")
    expectError(try removalEngine.prepare(RemovalIdentity(app: installed)))
    expectTrue(FileManager.default.fileExists(atPath: installed.path))
  }
  func testCaskOwnershipRequiresTheExactLink() throws {
    let installed = try removalFixture()
    let room = root.appendingPathComponent("Caskroom")
    let link = room.appendingPathComponent("test-cask/1.0/Uncatalogued.app")
    try FileManager.default.createDirectory(
      at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: link, withDestinationURL: URL(fileURLWithPath: installed.path))
    expectEqual(CaskIndex(rooms: [room]).owners[installed.path], Set(["test-cask"]))
    try bundle("Applications/Other/Uncatalogued.app", id: installed.bundleID)
    expectEqual(
      CaskIndex(rooms: [room]).owners[
        root.appendingPathComponent("Applications/Other/Uncatalogued.app").path], nil)
    let engine = RemovalEngine(
      roots: [root.appendingPathComponent("Applications")], caskRooms: [room],
      brew: BrewEngine(executable: "/usr/bin/false"))
    expectError(try engine.prepare(RemovalIdentity(app: installed)))
    expectTrue(FileManager.default.fileExists(atPath: installed.path))
  }
  func testNonCatalogRemovalPersistsIdentityAndInterruptedState() throws {
    let installed = try removalFixture()
    let identity = RemovalIdentity(
      app: installed, supportNames: ["Fixture"], groupIDs: ["group.test.fixture"])
    let plan = try removalEngine.prepare(identity)
    var entry = QueueEntry(plan: plan)
    entry.stage = .removing
    var state = SavedState()
    state.queue = [entry]
    state.removalSelection = [installed.path]
    let url = root.appendingPathComponent("state.json")
    try Persistence.save(state, to: url)
    let restored = try Persistence.read(url)
    expectEqual(restored.queue[0].removedApp, identity)
    expectEqual(restored.queue[0].removalMethod, .trash)
    expectEqual(restored.queue[0].stage, .interrupted)
    expectEqual(
      Library.removableSelection(
        state.removalSelection, catalog: [], installed: [installed], receipts: [:]),
      [installed.path])
    expectTrue(
      Library.removableSelection(state.removalSelection, catalog: [], installed: [], receipts: [:])
        .isEmpty)
  }
  func testGenericNamesAndSharedGroupsAreReviewedSeparately() throws {
    let installed = try removalFixture()
    let identity = RemovalIdentity(
      app: installed, groupIDs: ["group.test.fixture", "../../Documents"])
    try file("Library/Application Support/Uncatalogued/data", "12345678")
    try file("Library/Group Containers/group.test.fixture/data", "123")
    try file("Library/Application Support/Uncatalogued Other/precious")
    let scanner = LeftoverScanner(home: root)
    let report = scanner.scan(identity)
    expectEqual(report.items.count, 2)
    expectEqual(report.items.reduce(0) { $0 + $1.bytes }, 11)
    expectEqual(report.items.first { $0.reason == "name" }?.kind, .personal)
    expectEqual(report.items.first { $0.reason == "group" }?.selectable, false)
    let collision = InstalledApp(
      name: "Uncatalogued", bundleID: "another.vendor.app", path: "/Elsewhere/Uncatalogued.app",
      version: "1", store: false)
    let revised = scanner.scan(identity, installed: [collision])
    expectEqual(revised.items.first { $0.reason == "sharedName" }?.selectable, false)
  }
  func testConfirmedSandboxContainerAndTwoPartBundleID() throws {
    let installed = InstalledApp(
      name: "Notion fixture", bundleID: "notion.id",
      path: root.appendingPathComponent("Applications/Absent.app").path, version: "1", store: true)
    try file("Library/Containers/notion.id/Data/content", "personal")
    let metadata = root.appendingPathComponent(
      "Library/Containers/notion.id/.com.apple.containermanagerd.metadata.plist")
    let content = try PropertyListSerialization.data(
      fromPropertyList: ["MCMMetadataIdentifier": "notion.id"], format: .xml, options: 0)
    try content.write(to: metadata)
    let identity = RemovalIdentity(app: installed)
    let scanner = LeftoverScanner(home: root)
    let item = try requireValue(scanner.scan(identity).items.first)
    expectEqual(item.kind, .personal)
    expectTrue(item.selectable)
    let destination = try scanner.trash(item, for: identity, installed: [])
    defer { try? FileManager.default.moveItem(at: destination, to: item.url) }
    expectFalse(FileManager.default.fileExists(atPath: item.url.path))
  }
  func testLaunchAgentRequiresProgramInsideSelectedApp() throws {
    let path = root.appendingPathComponent("Applications/Absent.app").path
    let installed = InstalledApp(
      name: "Fixture", bundleID: "test.fixture.app", path: path, version: "1", store: false)
    let identity = RemovalIdentity(app: installed)
    let folder = root.appendingPathComponent("Library/LaunchAgents")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    func agent(_ file: String, _ program: String) throws {
      let data = try PropertyListSerialization.data(
        fromPropertyList: [
          "Label": "test.onenstall.fixture." + UUID().uuidString, "ProgramArguments": [program],
        ], format: .xml, options: 0)
      try data.write(to: folder.appendingPathComponent(file))
    }
    try agent("owned.plist", path + "/Contents/MacOS/helper")
    try agent("test.fixture.app.plist", "/Applications/Unrelated.app/Contents/MacOS/helper")
    try agent("traversal.plist", path + "/../Unrelated.app/Contents/MacOS/helper")
    let scanner = LeftoverScanner(home: root)
    let items = scanner.scan(identity).items
    expectEqual(items.map { $0.url.lastPathComponent }, ["owned.plist"])
    let item = try requireValue(items.first)
    expectEqual(item.reason, "launchAgent")
    let destination = try scanner.trash(item, for: identity, installed: [])
    defer { try? FileManager.default.moveItem(at: destination, to: item.url) }
    expectTrue(
      FileManager.default.fileExists(
        atPath: folder.appendingPathComponent("test.fixture.app.plist").path))
  }
  func testByHostAssociationUsesExactBundleAndUUID() throws {
    let identity = RemovalIdentity(catalog: app)
    try file("Library/Preferences/ByHost/\(app.bundleID).\(UUID().uuidString).plist")
    try file("Library/Preferences/ByHost/\(app.bundleID).other-product.plist")
    try file("Library/Preferences/ByHost/\(app.bundleID)Other.\(UUID().uuidString).plist")
    expectEqual(LeftoverScanner(home: root).scan(identity).items.count, 1)
  }
}

extension CoreTests {
  func caskRemovalFixture(fail: Bool = false) throws -> (InstalledApp, RemovalEngine, URL) {
    let installed = try removalFixture()
    let room = root.appendingPathComponent("Caskroom")
    let token = room.appendingPathComponent("fixture-cask")
    let metadata = token.appendingPathComponent(".metadata")
    let recorded = metadata.appendingPathComponent("1.0/20260101000000/Casks/fixture-cask.json")
    try FileManager.default.createDirectory(
      at: recorded.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: recorded)
    let artifacts: [[String: Any]] = [
      ["app": ["Uncatalogued.app"]],
      ["zap": [["trash": ["~/Library/Application Support/Personal"]]]],
    ]
    let receipt = metadata.appendingPathComponent("INSTALL_RECEIPT.json")
    try JSONSerialization.data(withJSONObject: [
      "uninstall_flight_blocks": false, "uninstall_artifacts": artifacts,
    ]).write(to: receipt)
    let link = token.appendingPathComponent("1.0/Uncatalogued.app")
    try FileManager.default.createDirectory(
      at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: link, withDestinationURL: URL(fileURLWithPath: installed.path))
    let script = root.appendingPathComponent("brew-fixture")
    let config = root.appendingPathComponent("fixture-config.json")
    try JSONSerialization.data(withJSONObject: [
      "path": installed.path, "moved": root.appendingPathComponent("Moved.app").path, "fail": fail,
    ]).write(to: config)
    let source = """
      #!/usr/bin/python3
      import sys, json, pathlib, os
      c = json.loads(pathlib.Path(__file__).with_name('fixture-config.json').read_text())
      args = sys.argv[1:]
      if args == ['list', '--cask', 'fixture-cask']:
          print(c['path'])
      elif args == ['uninstall', '--cask', 'fixture-cask']:
          if c['fail']: sys.exit(1)
          os.rename(c['path'], c['moved'])
      elif args == ['list', '--cask', '--versions']:
          if os.path.exists(c['path']): print('fixture-cask 1.0')
      else: sys.exit(99)
      """
    try Data(source.utf8).write(to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return (
      installed,
      RemovalEngine(
        roots: [root.appendingPathComponent("Applications")], caskRooms: [room],
        brew: BrewEngine(executable: script.path)), receipt
    )
  }
  func testExternalHomebrewUsesRecordedArtifactsAndVerifiesReceiptRemoval() throws {
    let (installed, engine, _) = try caskRemovalFixture()
    let plan = try engine.prepare(RemovalIdentity(app: installed))
    expectEqual(plan.method, .homebrew)
    expectEqual(plan.cask, "fixture-cask")
    let result = try engine.remove(plan, onStage: { _ in })
    expectEqual(result.trashPath, nil)
    expectEqual(result.remainingCopies, 0)
    expectFalse(FileManager.default.fileExists(atPath: installed.path))
  }
  func testHomebrewFailureDoesNotFallBackToDeletingBundle() throws {
    let (installed, engine, _) = try caskRemovalFixture(fail: true)
    let plan = try engine.prepare(RemovalIdentity(app: installed))
    expectError(try engine.remove(plan, onStage: { _ in }))
    expectTrue(FileManager.default.fileExists(atPath: installed.path))
  }
  func testHomebrewMetadataChangesAndScriptsInvalidateReview() throws {
    let (installed, engine, receipt) = try caskRemovalFixture()
    let identity = RemovalIdentity(app: installed)
    let plan = try engine.prepare(identity)
    let changed: [String: Any] = [
      "uninstall_flight_blocks": true, "uninstall_artifacts": [["app": ["Uncatalogued.app"]]],
    ]
    try JSONSerialization.data(withJSONObject: changed).write(to: receipt)
    expectError(try engine.remove(plan, onStage: { _ in }))
    expectError(try engine.prepare(identity))
    expectTrue(FileManager.default.fileExists(atPath: installed.path))
  }
  func testSharedAssociationAppearingAfterReviewBlocksCleanup() throws {
    let installed = InstalledApp(
      name: "Uncatalogued", bundleID: "test.fixture.app",
      path: root.appendingPathComponent("Applications/Absent.app").path, version: "1", store: false)
    let identity = RemovalIdentity(app: installed)
    try file("Library/Application Support/Uncatalogued/data")
    let scanner = LeftoverScanner(home: root, systemLibrary: nil)
    let item = try requireValue(scanner.scan(identity).items.first)
    let other = InstalledApp(
      name: "Uncatalogued", bundleID: "another.fixture.app", path: "/Elsewhere/Uncatalogued.app",
      version: "1", store: false)
    expectError(try scanner.trash(item, for: identity, installed: [other]))
    expectTrue(FileManager.default.fileExists(atPath: item.url.path))
  }
  func testSystemResiduesAreMeasuredButCannotBeTrashed() throws {
    let identity = RemovalIdentity(catalog: app)
    try file("SystemLibrary/Application Support/\(app.bundleID)/data", "123456789")
    let scanner = LeftoverScanner(
      home: root, systemLibrary: root.appendingPathComponent("SystemLibrary"))
    let item = try requireValue(scanner.scan(identity).items.first)
    expectEqual(item.kind, .system)
    expectEqual(item.bytes, 9)
    expectEqual(item.files, 1)
    expectTrue(item.complete)
    expectFalse(item.selectable)
    expectError(try scanner.trash(item, for: identity, installed: []))
  }
  func testLegacySavedStateWithoutRemovalMetadataStillLoads() throws {
    let url = try file(
      "old-state.json",
      """
      {"installSelection":["iina"],"removalSelection":[],"queue":[{"id":"6F5BE94B-80B3-4B26-AB76-BC70F63DCF6E","appID":"iina","name":"IINA","operation":"remove","stage":"succeeded","detail":"","date":0}],"history":[],"receipts":{}}
      """)
    let state = try Persistence.read(url)
    expectEqual(state.installSelection, ["iina"])
    expectEqual(state.queue[0].stage, .succeeded)
    expectEqual(state.queue[0].removedApp, nil)
  }
}
