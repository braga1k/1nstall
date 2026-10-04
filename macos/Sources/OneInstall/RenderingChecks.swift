import AppKit
import OneInstallCore

/// Exercises the real view/layer composition with isolated model data. No OS
/// input synthesis and no installation, preference or saved-state mutation.
@MainActor enum RenderingChecks {
  static func run(_ m: AppModel, window: NSWindow) async {
    do {
      var count = 0
      func check(_ condition: Bool, _ name: String) throws {
        guard condition else { throw OperationError("FAIL \(name)") }
        count += 1
        print("PASS \(name)")
      }
      let original = try? Data(contentsOf: m.stateURL)
      m.lessMotion = false
      try await Task.sleep(for: .milliseconds(300))
      m.changePage("uninstall")
      try await Task.sleep(for: .milliseconds(40))
      try check(
        m.page == "uninstall" && PerformanceHarness.arrivalPage == "uninstall",
        "Uninstall destination is live during its entrance")
      if !m.reduced {
        try check(
          PerformanceHarness.arrivalProgress > 0,
          "Entrance animation remains active after navigation")
      }
      m.changePage("install")
      try await Task.sleep(for: .milliseconds(40))
      try check(
        m.page == "install" && PerformanceHarness.arrivalPage == "install",
        "A second destination replaces the first before 200ms completion")
      m.search = "iina"
      try await Task.sleep(for: .milliseconds(20))
      try check(m.search == "iina" && m.page == "install", "Search accepts edits during entrance")
      m.lessMotion = true
      m.changePage("settings")
      try await Task.sleep(for: .milliseconds(40))
      try check(PerformanceHarness.arrivalProgress == 0, "Reduced motion removes entrance movement")
      let surface = LightSurface()
      surface.frame = NSRect(x: 20, y: 20, width: 100, height: 100)
      window.contentView!.addSubview(surface)
      surface.configure(
        color: .white.withAlphaComponent(0.1), corner: 18, radius: 230, enabled: true)
      PointerLights.shared.move(surface.convert(NSPoint(x: 30, y: 30), to: nil), in: window)
      try check(surface.visibleGlow, "Pointer light is visible on nearby surfaces")
      let previous = surface.glowPosition
      PointerLights.shared.move(surface.convert(NSPoint(x: 70, y: 60), to: nil), in: window)
      try check(
        surface.visibleGlow && surface.glowPosition != previous,
        "Pointer light follows movement without rebuilding SwiftUI")
      try check(
        surface.hitTest(NSPoint(x: 30, y: 30)) == nil,
        "Decorative light passes pointer clicks through")
      let tracker = LightTrackingView()
      try check(tracker.hitTest(.zero) == nil, "Tracking overlay passes pointer clicks through")
      surface.configure(color: .white, corner: 18, radius: 230, enabled: false)
      PointerLights.shared.move(surface.convert(NSPoint(x: 30, y: 30), to: nil), in: window)
      try check(!surface.visibleGlow, "Reduced motion hides and disables pointer light")
      surface.removeFromSuperview()
      try check(
        (try? Data(contentsOf: m.stateURL)) == original,
        "Rendering checks preserve real saved state")
      print("\(count) rendering checks; 0 failures")
      NSApp.terminate(nil)
    } catch {
      print(error)
      exit(1)
    }
  }
}
