import AppKit
import SwiftUI

/// Decorative light has no observable state: moving the mouse must never re-run
/// catalog filtering, layout or button construction. Core Animation moves only
/// the radial layers; all native views pass clicks through to SwiftUI.
@MainActor final class PointerLights {
  static let shared = PointerLights()
  private var tracedMoves = 0
  private let surfaces = NSHashTable<LightSurface>.weakObjects()
  func register(_ surface: LightSurface) { surfaces.add(surface) }
  func visibleCount(in window: NSWindow) -> Int {
    surfaces.allObjects.filter { $0.window === window && $0.visibleGlow }.count
  }
  func move(_ point: NSPoint?, in window: NSWindow?) {
    guard let window else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for surface in surfaces.allObjects where surface.window === window {
      surface.move(point)
    }
    CATransaction.commit()
    if PerformanceHarness.traceInteractions, point != nil, tracedMoves < 5 {
      tracedMoves += 1
      print(
        "Native pointer light: \(visibleCount(in: window)) visible layers; click-through tracking")
    }
  }
}

struct PointerLight: NSViewRepresentable {
  var color: Color
  var corner: CGFloat
  var radius: CGFloat
  var enabled: Bool
  func makeNSView(context: Context) -> LightSurface { LightSurface() }
  func updateNSView(_ view: LightSurface, context: Context) {
    view.configure(color: NSColor(color), corner: corner, radius: radius, enabled: enabled)
  }
}

final class LightSurface: NSView {
  private let glow = CAGradientLayer()
  private var radius: CGFloat = 0
  private var enabled = false
  private var lightColor: NSColor?
  var visibleGlow: Bool { !glow.isHidden }
  var glowPosition: CGPoint { glow.position }
  override var isFlipped: Bool { true }
  init() {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = true
    glow.type = .radial
    glow.startPoint = CGPoint(x: 0.5, y: 0.5)
    glow.endPoint = CGPoint(x: 1, y: 1)
    glow.locations = [0, 0.5, 1]
    glow.isHidden = true
    layer?.addSublayer(glow)
    PointerLights.shared.register(self)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  func configure(color: NSColor, corner: CGFloat, radius: CGFloat, enabled: Bool) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if lightColor != color {
      lightColor = color
      glow.colors = [
        color.cgColor, NSColor.white.withAlphaComponent(0.025).cgColor,
        NSColor.clear.cgColor,
      ]
    }
    if self.radius != radius {
      self.radius = radius
      glow.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
    }
    layer?.cornerRadius = corner
    self.enabled = enabled
    if !enabled { glow.isHidden = true }
    CATransaction.commit()
  }
  func move(_ point: NSPoint?) {
    guard enabled, let point, !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty else {
      glow.isHidden = true
      return
    }
    let local = convert(point, from: nil)
    let nearby = bounds.insetBy(dx: -radius, dy: -radius).contains(local)
    glow.isHidden = !nearby
    if nearby { glow.position = local }
  }
}

struct PointerTracking: NSViewRepresentable {
  var enabled: Bool
  func makeNSView(context: Context) -> LightTrackingView { LightTrackingView() }
  func updateNSView(_ view: LightTrackingView, context: Context) { view.enabled = enabled }
}

final class LightTrackingView: NSView {
  var enabled = false {
    didSet { if !enabled { PointerLights.shared.move(nil, in: window) } }
  }
  private var tracking: NSTrackingArea?
  private var benchmarkObserver: NSObjectProtocol?
  override var isFlipped: Bool { true }
  init() {
    super.init(frame: .zero)
    if PerformanceHarness.enabled {
      benchmarkObserver = NotificationCenter.default.addObserver(
        forName: PerformanceHarness.pointerNotification, object: nil, queue: .main
      ) { [weak self] event in
        MainActor.assumeIsolated {
          guard let self else { return }
          let point = (event.object as? CGPoint).map { self.convert($0, to: nil) }
          PointerLights.shared.move(point, in: self.window)
        }
      }
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  deinit {
    if let benchmarkObserver { NotificationCenter.default.removeObserver(benchmarkObserver) }
  }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func updateTrackingAreas() {
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(
      rect: .zero,
      options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
      owner: self, userInfo: nil)
    addTrackingArea(area)
    tracking = area
    super.updateTrackingAreas()
  }
  override func mouseMoved(with event: NSEvent) {
    if enabled { PointerLights.shared.move(event.locationInWindow, in: window) }
  }
  override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
  override func mouseExited(with event: NSEvent) { PointerLights.shared.move(nil, in: window) }
}
