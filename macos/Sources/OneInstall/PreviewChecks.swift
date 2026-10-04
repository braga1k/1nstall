import Foundation
import OneInstallCore

@MainActor enum PreviewChecks {
  static func run(_ m: AppModel) throws {
    func check(_ condition: Bool, _ name: String) throws {
      guard condition else { throw OperationError("FAIL \(name)") }
      print("PASS \(name)")
    }
    let original = try? Data(contentsOf: m.stateURL)
    m.search = "IINA"
    m.category = "players"
    m.installedOnly = true
    m.changePage("uninstall")
    m.search = "Fixture"
    m.changePage("install")
    try check(
      m.search == "IINA" && m.category == "players" && m.installedOnly,
      "Install filters survive navigation")
    m.changePage("install")
    try check(m.search == "IINA", "Selecting the current page preserves filters")
    m.changePage("uninstall")
    try check(m.search == "Fixture" && !m.installedOnly, "Uninstall has independent filters")
    m.changePage("install")
    let iina = m.apps.first { $0.id == "iina" }!
    m.inventory.apps = [
      .init(
        name: "IINA renamed", bundleID: iina.bundleID, path: "/fixture/IINA.app", version: "1",
        store: false)
    ]
    m.state.installSelection = ["blender"]
    m.applyProfile(Library.profiles[0], adding: true)
    try check(
      m.state.installSelection.contains("blender") && !m.state.installSelection.contains("iina"),
      "Add profile preserves selection and excludes installed bundles")
    m.applyProfile(Library.profiles[0], adding: false)
    try check(
      !m.state.installSelection.contains("blender")
        && m.state.installSelection.contains("rectangle"),
      "Replace profile updates only the selection")
    try check(m.state.queue.isEmpty && !m.busy, "Applying profiles never starts installation")
    var entry = QueueEntry(app: iina, operation: "remove")
    entry.stage = .failed
    m.state.queue = [entry]
    m.state.history = [entry]
    m.state.receipts[iina.id] = "/fixture/IINA.app"
    m.prepareRetry()
    try check(
      m.page == "uninstall" && m.selection == [iina.id] && !m.busy && !m.review,
      "Retry prepares a fresh review without starting removal")
    m.busy = true
    m.clearResults()
    try check(!m.state.queue.isEmpty, "Running queue cannot be cleared")
    m.busy = false
    m.clearResults()
    try check(
      m.state.queue.isEmpty && m.state.history.count == 1, "Clearing results preserves history")
    try check(
      (try? Data(contentsOf: m.stateURL)) == original, "Preview checks never overwrite real state")
    print("10 preview state checks; 0 failures")
  }
}
