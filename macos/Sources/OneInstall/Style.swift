import AppKit
import SwiftUI

struct Palette: Equatable {
  var dark = true
  var accent = true
  var demo = false
  func color(_ darkHex: UInt32, _ lightHex: UInt32) -> Color {
    let v = dark ? darkHex : lightHex
    let r = Double((v >> 16) & 255) / 255
    let g = Double((v >> 8) & 255) / 255
    let b = Double(v & 255) / 255
    if !accent { return Color(white: 0.2126 * r + 0.7152 * g + 0.0722 * b) }
    return Color(red: r, green: g, blue: b)
  }
  var ink: Color { color(0xF3F5F7, 0x1A1D25) }
  var secondary: Color { color(0xC2CADE, 0x414753) }
  var background: Color { color(0x0B1115, 0xDADDE6) }
  var action: Color {
    if !accent { return dark ? Color(white: 0.84) : Color(white: 0.13) }
    return demo ? Color(red: 0.41, green: 0.26, blue: 0.59) : Color(nsColor: .controlAccentColor)
  }
  var actionText: Color {
    guard accent else { return dark ? .black : .white }
    let c = NSColor(action).usingColorSpace(.sRGB) ?? .white
    let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    return luminance > 0.63 ? .black : .white
  }
  var panel: Gradient {
    Gradient(stops: [
      .init(color: color(0x464357, 0xF9F8FE), location: 0),
      .init(color: color(0x252932, 0xD3D6E5), location: 0.42),
      .init(color: color(0x1B252A, 0xCDD3E0), location: 0.76),
      .init(color: color(0x1C262A, 0xF0F1F7), location: 1),
    ])
  }
  var card: Gradient {
    Gradient(stops: [
      .init(color: color(0x2B2D36, 0xFCFBFF), location: 0),
      .init(color: color(0x242B31, 0xE4E6F0), location: 0.42),
      .init(color: color(0x232B30, 0xD7DDE8), location: 1),
    ])
  }
  var control: Gradient {
    Gradient(stops: [
      .init(color: color(0x393541, 0xFFFFFF), location: 0),
      .init(color: color(0x252B32, 0xD6DCEA), location: 0.48),
      .init(color: color(0x21292E, 0xC9D2E1), location: 1),
    ])
  }
  var edge: Gradient {
    Gradient(stops: [
      .init(color: color(0xD9D2FF, 0xFFFFFF).opacity(0.92), location: 0),
      .init(color: color(0x978BBF, 0xAEB8C8).opacity(0.76), location: 0.25),
      .init(color: color(0x4E447E, 0x758095).opacity(0.22), location: 0.55),
      .init(color: color(0x7593C9, 0xA4B4C7).opacity(0.55), location: 0.85),
      .init(color: color(0xCDF4FF, 0xFFFFFF).opacity(0.70), location: 1),
    ])
  }
  var cardEdge: Gradient {
    Gradient(stops: [
      .init(color: color(0x978EC4, 0xFFFFFF).opacity(dark ? 0.5 : 0.97), location: 0),
      .init(color: color(0x3F3A66, 0x919AAA).opacity(dark ? 0.15 : 0.5), location: 0.45),
      .init(color: color(0x6578A1, 0x9AA7B9).opacity(dark ? 0.28 : 0.8), location: 1),
    ])
  }
  var separator: Color { color(0x46516B, 0x87909F) }
}
private struct MotionReducedKey: EnvironmentKey { static let defaultValue = true }
private struct PointerLightingKey: EnvironmentKey { static let defaultValue = false }
private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette() }
extension EnvironmentValues {
  var motionReduced: Bool {
    get { self[MotionReducedKey.self] }
    set { self[MotionReducedKey.self] = newValue }
  }
  var pointerLighting: Bool {
    get { self[PointerLightingKey.self] }
    set { self[PointerLightingKey.self] = newValue }
  }
  var palette: Palette {
    get { self[PaletteKey.self] }
    set { self[PaletteKey.self] = newValue }
  }
}

struct Glass: ViewModifier {
  @Environment(\.palette) var p
  @Environment(\.colorSchemeContrast) var contrast
  @Environment(\.motionReduced) var reduced
  @Environment(\.pointerLighting) var pointerLighting
  var radius: CGFloat = 18
  var panel = false
  var control = false
  var selected = false
  var quiet = false
  @State private var hover = false
  func body(content: Content) -> some View {
    let _ = PerformanceHarness.surface()
    return content.background {
      let shape = RoundedRectangle(cornerRadius: radius)
      ZStack {
        shape.fill(
          LinearGradient(
            gradient: panel ? p.panel : control ? p.control : p.card,
            startPoint: .topLeading, endPoint: UnitPoint(x: 0.8, y: 1))
        )
        .opacity(quiet ? (p.dark ? 0.20 : 0.45) : 1)
        if selected { shape.fill(p.action.opacity(p.accent ? 0.22 : 0.10)) }
        if panel {
          shape.fill(
            RadialGradient(
              colors: [.white.opacity(p.dark ? 0.06 : 0.14), .clear], center: .topLeading,
              startRadius: 0, endRadius: 370))
        }
        PointerLight(
          color: p.action.opacity(panel ? 0.075 : 0.10), corner: radius,
          radius: panel ? 360 : 230,
          enabled: !reduced && pointerLighting
        )
        .allowsHitTesting(false).accessibilityHidden(true)
        if hover {
          shape.fill(.white.opacity(p.dark ? 0.025 : 0.13))
        }
        shape.stroke(
          LinearGradient(
            gradient: panel || control ? p.edge : p.cardEdge,
            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1
        )
        .opacity(quiet ? 0.30 : 1)
        if (selected && !control) || contrast == .increased {
          shape.stroke(
            selected ? p.action : p.secondary, lineWidth: contrast == .increased ? 1.5 : 1)
        }
        if hover { shape.stroke(p.secondary.opacity(0.6), lineWidth: 1) }
        if panel || control {
          shape.inset(by: 1).stroke(
            LinearGradient(
              colors: [.white.opacity(p.dark ? 0.13 : 0.65), .clear, .clear], startPoint: .top,
              endPoint: .bottom), lineWidth: 0.6)
        }
      }.shadow(color: .black.opacity(panel ? (p.dark ? 0.12 : 0.07) : 0), radius: 10, x: 0, y: 3)
        .allowsHitTesting(false)
    }
    .onHover { if !PerformanceHarness.suppressHover { hover = $0 } }
    .animation(reduced ? nil : .easeOut(duration: 0.16), value: hover)
  }
}
extension View {
  func glass(
    radius: CGFloat = 18, panel: Bool = false, control: Bool = false, selected: Bool = false,
    quiet: Bool = false
  ) -> some View {
    modifier(
      Glass(radius: radius, panel: panel, control: control, selected: selected, quiet: quiet))
  }
}
struct GlassButtonStyle: ButtonStyle {
  @Environment(\.palette) var p
  @Environment(\.motionReduced) var reduced
  @Environment(\.isEnabled) var enabled
  var prominent = false
  var selected = false
  var compact = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: compact ? 11 : 12, weight: .regular))
      .padding(.horizontal, compact ? 11 : 14).frame(minHeight: compact ? 34 : 36)
      // Include padding and the full visible pill in the button hit area.
      .contentShape(Capsule())
      .foregroundStyle(prominent ? p.actionText : p.ink)
      .background {
        if prominent {
          Capsule().fill(p.action).overlay(
            Capsule().stroke(.white.opacity(0.16), lineWidth: 1).padding(1))
        }
      }
      .glass(radius: 20, control: true, selected: selected)
      .animation(reduced ? nil : .easeOut(duration: 0.16), value: selected)
      .opacity(enabled ? 1 : 0.45)
      .scaleEffect(configuration.isPressed && !reduced ? 0.975 : 1)
      .animation(
        reduced ? nil : .spring(response: 0.24, dampingFraction: 0.8),
        value: configuration.isPressed)
  }
}
struct CardPressStyle: ButtonStyle {
  @Environment(\.motionReduced) var reduced
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.contentShape(Rectangle())
      .scaleEffect(configuration.isPressed && !reduced ? 0.975 : 1)
      .animation(
        reduced ? nil : .spring(response: 0.22, dampingFraction: 0.7),
        value: configuration.isPressed)
  }
}

/// Animate only the live destination. No departing interactive tree is retained,
/// and a new trigger restarts this short decorative motion immediately.
struct PageArrival: ViewModifier {
  var page: String
  var reduced: Bool
  func body(content: Content) -> some View {
    content.keyframeAnimator(initialValue: 0.0, trigger: page) { view, progress in
      let _ = PerformanceHarness.arrival(page, progress: reduced ? 0 : progress)
      view.offset(y: reduced ? 0 : 5 * progress).opacity(reduced ? 1 : 1 - 0.08 * progress)
    } keyframes: { _ in
      MoveKeyframe(1.0)
      CubicKeyframe(0.0, duration: reduced ? 0 : 0.20)
    }
  }
}

struct SelectionAnchors: PreferenceKey {
  static let defaultValue: [String: Anchor<CGRect>] = [:]
  static func reduce(
    value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]
  ) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}
struct SelectionFlight: View {
  let event: SelectionEvent
  let start: CGPoint
  let end: CGPoint
  @Environment(\.palette) var p
  @State private var arrived = false
  var body: some View {
    Text(event.app.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
      .padding(.horizontal, 13).padding(.vertical, 8)
      .background(Capsule().fill(p.action)).foregroundStyle(p.actionText)
      .shadow(color: p.action.opacity(0.20), radius: 14, y: 4)
      .scaleEffect(arrived ? 0.70 : 1)
      .opacity(arrived ? 0 : 0.96)
      .position(arrived ? end : start)
      .onAppear { withAnimation(.easeInOut(duration: 0.48)) { arrived = true } }
      .allowsHitTesting(false).accessibilityHidden(true)
  }
}
struct Mark: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    // Original 1nstall brand mark, preserved from assets/brand-mark.svg.
    p.move(to: CGPoint(x: 776.575, y: 602.434))
    p.addCurve(
      to: CGPoint(x: 812.326, y: 602.081), control1: CGPoint(x: 785.538, y: 601.583),
      control2: CGPoint(x: 802.689, y: 602.073))
    p.addLine(to: CGPoint(x: 878.049, y: 602.118))
    p.addLine(to: CGPoint(x: 936.903, y: 601.89))
    p.addCurve(
      to: CGPoint(x: 987.166, y: 607.759), control1: CGPoint(x: 955.684, y: 601.813),
      control2: CGPoint(x: 969.601, y: 599.689))
    p.addCurve(
      to: CGPoint(x: 1020.57, y: 705.245), control1: CGPoint(x: 1028.02, y: 626.527),
      control2: CGPoint(x: 1020.51, y: 668.627))
    p.addLine(to: CGPoint(x: 1020.68, y: 830.212))
    p.addCurve(
      to: CGPoint(x: 1022.17, y: 905.048), control1: CGPoint(x: 1020.65, y: 850.23),
      control2: CGPoint(x: 1019.61, y: 886.403))
    p.addCurve(
      to: CGPoint(x: 1134.47, y: 1023.25), control1: CGPoint(x: 1029.98, y: 964.649),
      control2: CGPoint(x: 1075.35, y: 1012.4))
    p.addCurve(
      to: CGPoint(x: 1231, y: 1025.36), control1: CGPoint(x: 1157.23, y: 1027.2),
      control2: CGPoint(x: 1205.99, y: 1025.52))
    p.addLine(to: CGPoint(x: 1348.53, y: 1025.01))
    p.addCurve(
      to: CGPoint(x: 1425.21, y: 1037.65), control1: CGPoint(x: 1374.62, y: 1024.86),
      control2: CGPoint(x: 1403.63, y: 1020.44))
    p.addCurve(
      to: CGPoint(x: 1447.3, y: 1100.13), control1: CGPoint(x: 1446.84, y: 1054.91),
      control2: CGPoint(x: 1447.44, y: 1074.81))
    p.addCurve(
      to: CGPoint(x: 1447.23, y: 1222.88), control1: CGPoint(x: 1447.06, y: 1141.07),
      control2: CGPoint(x: 1447.35, y: 1181.94))
    p.addCurve(
      to: CGPoint(x: 1441.11, y: 1306), control1: CGPoint(x: 1447.24, y: 1252.2),
      control2: CGPoint(x: 1447.96, y: 1277.04))
    p.addCurve(
      to: CGPoint(x: 1405.08, y: 1379.31), control1: CGPoint(x: 1434.74, y: 1332.82),
      control2: CGPoint(x: 1422.43, y: 1357.88))
    p.addCurve(
      to: CGPoint(x: 1273.59, y: 1446.09), control1: CGPoint(x: 1370.54, y: 1421.8),
      control2: CGPoint(x: 1327.06, y: 1440.54))
    p.addCurve(
      to: CGPoint(x: 1171.09, y: 1446.22), control1: CGPoint(x: 1245.08, y: 1447.74),
      control2: CGPoint(x: 1200.8, y: 1446.15))
    p.addLine(to: CGPoint(x: 1115.44, y: 1446.39))
    p.addCurve(
      to: CGPoint(x: 1047.55, y: 1432.73), control1: CGPoint(x: 1090.17, y: 1446.47),
      control2: CGPoint(x: 1068.52, y: 1449.46))
    p.addCurve(
      to: CGPoint(x: 1028.23, y: 1402.48), control1: CGPoint(x: 1037.92, y: 1425.08),
      control2: CGPoint(x: 1031.11, y: 1414.43))
    p.addCurve(
      to: CGPoint(x: 1026.37, y: 1340.39), control1: CGPoint(x: 1024.9, y: 1388.81),
      control2: CGPoint(x: 1026.35, y: 1356.04))
    p.addLine(to: CGPoint(x: 1026.49, y: 1222.34))
    p.addCurve(
      to: CGPoint(x: 1025.27, y: 1146.87), control1: CGPoint(x: 1026.57, y: 1200.81),
      control2: CGPoint(x: 1027.62, y: 1167.15))
    p.addCurve(
      to: CGPoint(x: 919.163, y: 1026.3), control1: CGPoint(x: 1018.03, y: 1088.7),
      control2: CGPoint(x: 975.945, y: 1040.87))
    p.addCurve(
      to: CGPoint(x: 819.403, y: 1021.71), control1: CGPoint(x: 894.037, y: 1019.75),
      control2: CGPoint(x: 847.385, y: 1021.73))
    p.addLine(to: CGPoint(x: 699.896, y: 1021.69))
    p.addCurve(
      to: CGPoint(x: 622.004, y: 1008.45), control1: CGPoint(x: 673.681, y: 1021.74),
      control2: CGPoint(x: 643.582, y: 1026.46))
    p.addCurve(
      to: CGPoint(x: 600.977, y: 933.823), control1: CGPoint(x: 597.393, y: 987.918),
      control2: CGPoint(x: 600.943, y: 962.864))
    p.addLine(to: CGPoint(x: 601.011, y: 874.591))
    p.addCurve(
      to: CGPoint(x: 644.956, y: 667.2), control1: CGPoint(x: 601.005, y: 799.058),
      control2: CGPoint(x: 591.75, y: 728.492))
    p.addCurve(
      to: CGPoint(x: 776.575, y: 602.434), control1: CGPoint(x: 679.803, y: 627.057),
      control2: CGPoint(x: 724.069, y: 606.658))
    p.closeSubpath()
    p.move(to: CGPoint(x: 640.349, y: 1224.31))
    p.addCurve(
      to: CGPoint(x: 704.008, y: 1223.71), control1: CGPoint(x: 660.715, y: 1221.76),
      control2: CGPoint(x: 683.364, y: 1223.71))
    p.addCurve(
      to: CGPoint(x: 783.348, y: 1224.14), control1: CGPoint(x: 730.083, y: 1223.7),
      control2: CGPoint(x: 757.399, y: 1222.05))
    p.addCurve(
      to: CGPoint(x: 802.46, y: 1228.58), control1: CGPoint(x: 789.668, y: 1224.65),
      control2: CGPoint(x: 796.686, y: 1225.92))
    p.addCurve(
      to: CGPoint(x: 827.349, y: 1257.56), control1: CGPoint(x: 813.947, y: 1233.89),
      control2: CGPoint(x: 823.586, y: 1245.57))
    p.addCurve(
      to: CGPoint(x: 829.407, y: 1398.14), control1: CGPoint(x: 831.505, y: 1270.81),
      control2: CGPoint(x: 831.16, y: 1380.08))
    p.addCurve(
      to: CGPoint(x: 824.731, y: 1416.38), control1: CGPoint(x: 828.797, y: 1404.43),
      control2: CGPoint(x: 827.747, y: 1410.76))
    p.addCurve(
      to: CGPoint(x: 790.115, y: 1443.7), control1: CGPoint(x: 817.248, y: 1430.35),
      control2: CGPoint(x: 805.139, y: 1439.19))
    p.addCurve(
      to: CGPoint(x: 699.976, y: 1428.73), control1: CGPoint(x: 765.019, y: 1449.44),
      control2: CGPoint(x: 723.087, y: 1439.7))
    p.addCurve(
      to: CGPoint(x: 610.579, y: 1328.65), control1: CGPoint(x: 658.195, y: 1408.4),
      control2: CGPoint(x: 626.085, y: 1372.45))
    p.addCurve(
      to: CGPoint(x: 640.349, y: 1224.31), control1: CGPoint(x: 596.576, y: 1288.9),
      control2: CGPoint(x: 590.815, y: 1240.29))
    p.closeSubpath()
    return p.applying(
      CGAffineTransform(translationX: -596, y: -598).concatenating(
        CGAffineTransform(scaleX: rect.width / 855, y: rect.height / 853)))
  }
}
