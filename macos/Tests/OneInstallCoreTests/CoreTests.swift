import Foundation
import OneInstallCore

final class CoreTests: CheckSuite {
  func testRemovalSelectionRequiresTheOwnedCopyToStillExist() throws {
    let catalog = try Catalog.load()
    let app = catalog[0]
    let owned = InstalledApp(
      name: app.name, bundleID: app.bundleID, path: "/fixture/Owned.app", version: "1", store: false
    )
    let other = InstalledApp(
      name: app.name, bundleID: app.bundleID, path: "/fixture/Other.app", version: "1", store: false
    )
    let receipts = [app.id: owned.path]
    expectEqual(
      Library.removableSelection(
        [app.id], catalog: catalog, installed: [owned], receipts: receipts), Set([app.id]))
    expectTrue(
      Library.removableSelection([app.id], catalog: catalog, installed: [other], receipts: receipts)
        .isEmpty)
    expectTrue(
      Library.removableSelection([app.id], catalog: catalog, installed: [], receipts: receipts)
        .isEmpty)
    expectTrue(
      Library.removableSelection([app.id], catalog: catalog, installed: [owned], receipts: [:])
        .isEmpty)
  }
  func testLibraryCategoriesAndProfilesStayConnected() throws {
    let catalog = try Catalog.load()
    expectEqual(Set(Library.categories.map(\.id)).count, Library.categories.count)
    for app in catalog {
      let category = try requireValue(Library.categories.first { $0.id == app.category })
      expectTrue(Library.groups.contains { $0.id == category.group })
      expectTrue(Library.matches(app.category, filter: category.group))
      expectTrue(Library.matches(app.category, filter: "all"))
      expectFalse(Library.matches(app.category, filter: "not-a-category"))
    }
    for profile in Library.profiles {
      expectFalse(profile.apps.isEmpty)
      for id in profile.apps {
        expectTrue(catalog.contains { $0.id == id }, "Missing profile app: \(id)")
      }
    }
  }
  func testProfilesSkipInstalledBundlesAndUnknownIDs() throws {
    let catalog = try Catalog.load()
    let app = catalog[0]
    let installed = InstalledApp(
      name: "Renamed app", bundleID: app.bundleID, path: "/fixture/Renamed.app", version: "older",
      store: false)
    expectEqual(
      Library.selectable([app.id, app.id, "unknown"], catalog: catalog, installed: []),
      Set([app.id]))
    expectTrue(
      Library.selectable([app.id, "unknown"], catalog: catalog, installed: [installed]).isEmpty)
  }
  func testQueueSummaryNeverCallsGuidedOrInterruptedSuccess() throws {
    var entries: [QueueEntry] = []
    for stage in [QueueStage.succeeded, .guided, .interrupted, .failed, .waiting, .verifying] {
      var entry = QueueEntry(app: app, operation: "install")
      entry.stage = stage
      entries.append(entry)
    }
    let summary = QueueSummary(entries)
    expectEqual(summary.total, 6)
    expectEqual(summary.completed, 4)
    expectEqual(summary.verified, 1)
    expectEqual(summary.attention, 2)
    expectEqual(summary.guided, 1)
    expectEqual(QueueSummary([]).fraction, 0)
  }
  var root: URL!
  var app: CatalogApp!
  override func setUpWithError() throws {
    let base = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment["ONEINSTALL_TEST_ROOT"] ?? FileManager
        .default.currentDirectoryPath + "/work/test-fixtures")
    root = base.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    app = CatalogApp(
      id: "fixture", name: "Disposable Fixture", category: "tools", summaryEN: "", summaryPT: "",
      bundleID: "org.onenstall.fixture", appName: "Fixture.app", website: "https://example.invalid",
      source: "homebrew", version: "1", minimumOS: "14", architecture: "Universal", sha256: "abc",
      verified: "2026-10-04", supportNames: ["Fixture"])
  }
  override func tearDownWithError() throws {
    if let root { try FileManager.default.removeItem(at: root) }
  }
  @discardableResult func file(_ relative: String, _ data: String = "12345") throws -> URL {
    let url = root.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(data.utf8).write(to: url)
    return url
  }
  func bundle(_ path: String, id: String) throws {
    let url = root.appendingPathComponent(path + "/Contents/Info.plist")
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(
      fromPropertyList: [
        "CFBundleIdentifier": id, "CFBundleName": "Fixture", "CFBundleShortVersionString": "1.0",
      ], format: .xml, options: 0)
    try data.write(to: url)
  }
  func testInventoryFindsNestedFoldersButNotEmbeddedHelpers() throws {
    try bundle("Applications/Vendor/Fixture.app", id: app.bundleID)
    try bundle(
      "Applications/Vendor/Fixture.app/Contents/Helpers/Helper.app", id: "org.helper.fixture")
    let result = Inventory.scan(roots: [root.appendingPathComponent("Applications")])
    expectEqual(result.apps.map(\.bundleID), [app.bundleID])
    expectTrue(result.warnings.isEmpty)
  }
  func testInventoryKeepsSeparateCopiesWithSameBundleID() throws {
    try bundle("Applications/Fixture.app", id: app.bundleID)
    try bundle("Applications/Other.app", id: app.bundleID)
    expectEqual(Inventory.scan(roots: [root.appendingPathComponent("Applications")]).apps.count, 2)
  }
  func testExactAssociationsAndRealCounts() throws {
    try file("Library/Caches/\(app.bundleID)/one")
    try file("Library/Caches/\(app.bundleID)/two", "123")
    try file("Library/Preferences/\(app.bundleID).plist", "1234")
    try file("Library/Application Support/UnrelatedFixture/data")
    let result = LeftoverScanner(home: root).scan(app)
    expectEqual(result.items.count, 2)
    expectEqual(result.items.reduce(0) { $0 + $1.bytes }, 12)
    expectEqual(result.items.reduce(0) { $0 + $1.files }, 3)
    expectTrue(result.items.allSatisfy(\.complete))
  }
  func testSymlinkAncestorsAndLeavesCannotEscape() throws {
    let outside = try file("Documents/precious").deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Library"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("Library/Caches"), withDestinationURL: outside)
    try file("Documents/\(app.bundleID)")
    let result = LeftoverScanner(home: root).scan(app)
    expectTrue(result.items.isEmpty)
    expectFalse(result.warnings.isEmpty)
    expectTrue(
      FileManager.default.fileExists(atPath: outside.appendingPathComponent("precious").path))
  }
  func testNestedSymlinksMakeMeasurementNonSelectable() throws {
    let target = try file("Documents/precious")
    let cache = root.appendingPathComponent("Library/Caches/\(app.bundleID)")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: cache.appendingPathComponent("link"), withDestinationURL: target)
    let item = try requireValue(LeftoverScanner(home: root).scan(app).items.first)
    expectFalse(item.complete)
    expectFalse(item.selectable)
  }
  func testChangedFilesRefuseStaleReview() throws {
    let path = try file("Library/Caches/\(app.bundleID)/data")
    let scanner = LeftoverScanner(home: root)
    let item = try requireValue(LeftoverScanner(home: root).scan(app).items.first)
    try Data("changed".utf8).write(to: path)
    expectError(try scanner.trash(item, for: app, installed: []))
    expectTrue(FileManager.default.fileExists(atPath: path.path))
  }
  func testInstalledCopiesBlockCleanup() throws {
    try file("Library/Preferences/\(app.bundleID).plist")
    try bundle("Applications/Fixture.app", id: app.bundleID)
    let item = try requireValue(LeftoverScanner(home: root).scan(app).items.first)
    expectError(
      try LeftoverScanner(home: root).trash(
        item, for: app,
        installed: Inventory.scan(roots: [root.appendingPathComponent("Applications")]).apps))
  }
  func testContainersStayProtected() throws {
    try file("Library/Containers/\(app.bundleID)/data")
    let item = try requireValue(LeftoverScanner(home: root).scan(app).items.first)
    expectEqual(item.kind, .shared)
    expectFalse(item.selectable)
    expectError(try LeftoverScanner(home: root).trash(item, for: app, installed: []))
  }
  func testTrashAndRestoreOnlyDisposableFixture() throws {
    try file("Library/Caches/\(app.bundleID)/data")
    let scanner = LeftoverScanner(home: root)
    let item = try requireValue(LeftoverScanner(home: root).scan(app).items.first)
    let destination = try scanner.trash(item, for: app, installed: [])
    expectFalse(FileManager.default.fileExists(atPath: item.url.path))
    expectTrue(FileManager.default.fileExists(atPath: destination.path))
    try FileManager.default.moveItem(at: destination, to: item.url)
    expectEqual(
      try String(contentsOf: item.url.appendingPathComponent("data"), encoding: .utf8), "12345")
  }
  func testRestartNeverTurnsUnfinishedOperationIntoSuccess() throws {
    var state = SavedState()
    state.installSelection = ["fixture"]
    var entry = QueueEntry(app: app, operation: "install")
    entry.stage = .installing
    state.queue = [entry]
    let url = root.appendingPathComponent("state.json")
    try Persistence.save(state, to: url)
    let restored = try Persistence.read(url)
    expectEqual(restored.queue[0].stage, .interrupted)
    expectEqual(restored.installSelection, ["fixture"])
  }
  func testProcessArgumentsAreNotShellCode() throws {
    let result = try Command.run("/usr/bin/printf", ["%s", "$(touch forbidden); 'quoted'"])
    expectEqual(result.code, 0)
    expectEqual(result.output, "$(touch forbidden); 'quoted'")
  }
  func testTimeoutIsAnError() throws {
    expectError(try Command.run("/bin/sleep", ["3"], timeout: 0.1))
  }
  func testUnownedRemovalIsRejectedWithoutInvokingBrew() throws {
    let engine = BrewEngine(executable: "/usr/bin/false", appDirectory: root)
    expectError(
      try engine.remove(
        app, receipt: "/Applications/Personal.app", onStage: { _ in }, log: { _ in }))
  }
  func testChangedCaskOrPrivilegedInstallerIsRejected() throws {
    let script = root.appendingPathComponent("brew-fixture")
    func mock(_ extra: [String: Any]) throws {
      var cask: [String: Any] = [
        "version": "1", "sha256": "abc", "disabled": false, "deprecated": false,
        "artifacts": [["app": ["Fixture.app"]]],
      ]
      cask.merge(extra) { _, new in new }
      let json = String(
        decoding: try JSONSerialization.data(withJSONObject: ["casks": [cask]]), as: UTF8.self)
      let text = "#!/bin/sh\nprintf '%s' '" + json + "'\n"
      try Data(text.utf8).write(to: script)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    }
    let engine = BrewEngine(executable: script.path, appDirectory: root)
    try mock([:])
    try engine.preflight(app)
    try mock(["version": "2"])
    expectError(try engine.preflight(app))
    try mock(["disabled": true])
    expectError(try engine.preflight(app))
    try mock(["artifacts": [["pkg": ["Privileged.pkg"]]]])
    expectError(try engine.preflight(app))
  }
  func testCatalogAutomaticEntriesHaveChecksumsAndUniqueIdentities() throws {
    let catalog = try Catalog.load()
    expectEqual(Set(catalog.map(\.id)).count, catalog.count)
    for app in catalog where app.automatic {
      expectEqual(app.sha256?.count, 64)
      expectTrue(app.website.hasPrefix("https://"))
      expectFalse(app.bundleID.isEmpty)
    }
  }
}

final class LiveBrewTests: CheckSuite {
  func testTwoDisposableRealInstallsAndRemovals() throws {
    guard let directory = ProcessInfo.processInfo.environment["ONEINSTALL_LIVE_TEST_APPDIR"] else {
      throw SkipCheck("Explicit disposable app directory required for live Homebrew test")
    }
    let appDirectory = URL(fileURLWithPath: directory).standardizedFileURL
    guard appDirectory.path.contains("/work/"), !FileManager.default.fileExists(atPath: directory)
    else { throw OperationError("Use a new isolated work directory") }
    try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
    let engine = BrewEngine(appDirectory: appDirectory)
    let catalog = try Catalog.load()
    for token in ["rectangle", "iina"] {
      let app = try requireValue(catalog.first { $0.id == token })
      expectFalse(
        Inventory.scan().apps.contains { $0.bundleID == app.bundleID },
        "Never use an existing personal app as a fixture")
      let log: (String) -> Void = { print($0, terminator: "") }
      let stage: (QueueStage) -> Void = { print("STAGE \($0.rawValue)") }
      let roots = Inventory.roots + [appDirectory]
      let receipt = try engine.install(app, inventoryRoots: roots, onStage: stage, log: log)
      expectTrue(
        Inventory.scan(roots: [appDirectory]).apps.contains { $0.bundleID == app.bundleID })
      try engine.remove(app, receipt: receipt, inventoryRoots: roots, onStage: stage, log: log)
      expectFalse(FileManager.default.fileExists(atPath: receipt))
      print("VERIFIED install → identity/arm64 → uninstall → absent: \(token)")
    }
  }
}
