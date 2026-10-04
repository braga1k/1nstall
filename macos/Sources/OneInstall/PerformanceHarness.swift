import AppKit
import Darwin
import Foundation
import OneInstallCore

/// Opt-in, repeatable application benchmark. No OS input synthesis, installs,
/// preferences or saved selections; fixture contents are identical between builds.
@MainActor enum PerformanceHarness {
  static let enabled = CommandLine.arguments.contains("--benchmark")
  static let suppressHover =
    enabled || CommandLine.arguments.contains("--capture")
    || CommandLine.arguments.contains("--render-checks")
  static let traceInteractions = CommandLine.arguments.contains("--trace-interactions")
  private static var lastNavigation = 0.0
  static func navigation(_ page: String) {
    guard traceInteractions else { return }
    let now = ProcessInfo.processInfo.systemUptime
    let age = NSApp.currentEvent.map { (now - $0.timestamp) * 1000 } ?? -1
    print(
      "Navigation accepted: \(page); event age \(String(format: "%.2f", age))ms; interval \(String(format: "%.2f", (now - lastNavigation) * 1000))ms"
    )
    lastNavigation = now
  }
  nonisolated static let renderingChecks = CommandLine.arguments.contains("--render-checks")
  private nonisolated static let arrivalProbe = ArrivalProbe()
  static var arrivalPage: String { arrivalProbe.snapshot.0 }
  static var arrivalProgress: Double { arrivalProbe.snapshot.1 }
  nonisolated static func arrival(_ page: String, progress: Double) {
    if renderingChecks { arrivalProbe.record(page, progress: progress) }
  }
  static var started = 0.0
  static var roots = 0
  static var surfaces = 0
  static let pointerNotification = Notification.Name("1nstall.benchmark.pointer")
  static func root() { if enabled { roots += 1 } }
  static func surface() { if enabled { surfaces += 1 } }
  static func cpu() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
      + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
  }
  static func run(model: AppModel, window: NSWindow, destination: URL) async {
    do {
      let ready = (ProcessInfo.processInfo.systemUptime - started) * 1000
      let ids: Set<String> = [
        "blender", "brave-browser", "firefox", "iina", "keka", "localsend", "obsidian", "raycast",
        "rectangle", "spotify", "visual-studio-code", "vlc", "final-cut-pro", "logic-pro", "motion",
      ]
      model.apps = model.apps.filter { ids.contains($0.id) }
      model.state = SavedState()
      model.lessMotion = false
      model.inventory.apps = (0..<200).map { index in
        let app = model.apps[index % model.apps.count]
        return InstalledApp(
          name: app.name + " \(index)", bundleID: app.bundleID,
          path: "/Benchmark Fixtures/\(index)/" + app.appName, version: "1", store: false)
      }
      let scanStart = ProcessInfo.processInfo.systemUptime
      let inventory = await Task.detached { Inventory.scan() }.value
      let scanMS = (ProcessInfo.processInfo.systemUptime - scanStart) * 1000
      var results: [[String: Any]] = []
      for phase in [
        "idle", "install-pointer", "uninstall-pointer", "settings-pointer", "search", "selection",
        "navigation",
      ] {
        model.page =
          phase.hasPrefix("uninstall")
          ? "uninstall" : phase.hasPrefix("settings") ? "settings" : "install"
        model.search = ""
        model.state.installSelection = []
        NotificationCenter.default.post(name: pointerNotification, object: nil)
        try await Task.sleep(for: .milliseconds(500))
        roots = 0
        surfaces = 0
        let begin = ProcessInfo.processInfo.systemUptime
        let cpuBegin = cpu()
        var previous = begin
        var ticks: [Double] = []
        let iterations = phase == "navigation" ? 24 : 120
        for i in 0..<iterations {
          if phase.contains("pointer") {
            let point = CGPoint(x: 30 + Double(i * 37 % 1170), y: 35 + Double(i * 23 % 760))
            NotificationCenter.default.post(name: pointerNotification, object: point)
          } else if phase == "search" {
            model.search = ["i", "ii", "iina", "", "fire", "", "rect", ""][i % 8]
          } else if phase == "selection" {
            let app = model.apps[i % model.apps.count]
            model.state.installSelection = [app.id]
          } else if phase == "navigation" {
            model.changePage(["install", "uninstall", "settings"][i % 3])
          }
          try await Task.sleep(for: .milliseconds(phase == "navigation" ? 80 : 16))
          let now = ProcessInfo.processInfo.systemUptime
          ticks.append((now - previous) * 1000)
          previous = now
        }
        let cpuSeconds = cpu() - cpuBegin
        ticks.sort()
        let visibleLights = PointerLights.shared.visibleCount(in: window)
        if phase.contains("pointer") && visibleLights == 0 {
          throw OperationError("Pointer phase has no visible light layers")
        }
        let row: [String: Any] = [
          "phase": phase, "iterations": iterations,
          "wallSeconds": ProcessInfo.processInfo.systemUptime - begin, "cpuSeconds": cpuSeconds,
          "medianTickMS": ticks[ticks.count / 2],
          "p95TickMS": ticks[Int(Double(ticks.count - 1) * 0.95)],
          "maxTickMS": ticks.last!, "rootEvaluations": roots, "glassEvaluations": surfaces,
          "visibleLightLayersAtEnd": visibleLights,
        ]
        results.append(row)
        print(
          "\(phase): CPU \(String(format: "%.3f", cpuSeconds))s; root \(roots); glass \(surfaces)")
      }
      let report: [String: Any] = [
        "method":
          "Release build; internal events on real NSHostingView; 1240x840pt; packaged catalog and 200 installed fixtures. Tick interval includes a 16ms sleep (80ms for navigation); not display FPS. CPU excludes WindowServer. No real state writes or operations.",
        "mainToWindowMS": ready, "inventoryReadMS": scanMS, "inventoryCount": inventory.apps.count,
        "phases": results,
      ]
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        .write(to: destination, options: .atomic)
      NSApp.terminate(nil)
    } catch {
      print("Benchmark failed: \(error)")
      exit(1)
    }
  }
}

// Keyframe rendering may run outside the main actor. This opt-in diagnostic
// records a snapshot without scheduling work or invalidating any view.
private final class ArrivalProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var value = ("", 0.0)
  var snapshot: (String, Double) {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
  func record(_ page: String, progress: Double) {
    lock.lock()
    value = (page, progress)
    lock.unlock()
  }
}
