import AppKit
import SwiftUI

struct Palette {
  var dark = true
  var accent = true
  var demo = false
  func color(_ darkHex: UInt32, _ lightHex: UInt32) -> Color {
    let v = dark ? darkHex : lightHex
    let r = Double((v >> 16) & 255) / 255
    let g = Double((v >> 8) & 255) / 255
    let b = Double(v & 255) / 255
    if !accent {
      let grey = 0.2126 * r + 0.7152 * g + 0.0722 * b
      return Color(white: grey)
    }
    return Color(red: r, green: g, blue: b)
  }
  var ink: Color { color(0xF3F5F7, 0x191B23) }
  var secondary: Color { color(0xC2CADE, 0x464A56) }
  var background: Color { color(0x0D1418, 0xD7DBE5) }
  var action: Color {
    if !accent { return dark ? Color(white: 0.84) : Color(white: 0.13) }
    return demo ? Color(red: 0.41, green: 0.26, blue: 0.59) : Color(nsColor: .controlAccentColor)
  }
  var actionText: Color { accent ? .white : (dark ? .black : .white) }
  var panel: [Color] {
    [color(0x454457, 0xF9F8FD), color(0x22282F, 0xCCD2E0), color(0x1A2328, 0xF0F1F7)]
  }
  var card: [Color] { [color(0x2D303A, 0xFBFAFF), color(0x222A2F, 0xD6DBE6)] }
  var control: [Color] { [color(0x35333F, 0xFFFFFF), color(0x20272D, 0xC9D1E0)] }
  var edge: [Color] {
    [color(0xC7B5F3, 0xFFFFFF).opacity(dark ? 0.85 : 1), color(0x6D7690, 0xA6ABC0).opacity(0.6)]
  }
  var separator: Color { secondary.opacity(0.28) }
}
private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette() }
extension EnvironmentValues {
  var palette: Palette {
    get { self[PaletteKey.self] }
    set { self[PaletteKey.self] = newValue }
  }
}
struct Glass: ViewModifier {
  @Environment(\.palette) var p
  @EnvironmentObject var m: AppModel
  var radius: CGFloat = 18
  var panel = false
  var control = false
  var selected = false
  @State private var pointer = UnitPoint(x: 0.3, y: 0.1)
  @State private var hover = false
  func body(content: Content) -> some View {
    content.background {
      RoundedRectangle(cornerRadius: radius).fill(
        LinearGradient(
          colors: panel ? p.panel : control ? p.control : p.card, startPoint: .topLeading,
          endPoint: .bottomTrailing))
      if selected {
        RoundedRectangle(cornerRadius: radius).fill(p.action.opacity(p.accent ? 0.20 : 0.12))
      }
      RoundedRectangle(cornerRadius: radius).fill(
        RadialGradient(
          colors: [Color.white.opacity(panel ? 0.09 : 0.045), .clear], center: .topLeading,
          startRadius: 0, endRadius: panel ? 420 : 150))
      if hover {
        RoundedRectangle(cornerRadius: radius).fill(
          RadialGradient(
            colors: [p.action.opacity(0.18), Color.white.opacity(0.05), .clear], center: pointer,
            startRadius: 0, endRadius: 220))
      }
    }
    .overlay(
      RoundedRectangle(cornerRadius: radius).stroke(
        LinearGradient(colors: p.edge, startPoint: .topLeading, endPoint: .bottomTrailing),
        lineWidth: selected ? 1.1 : 0.7
      ).allowsHitTesting(false)
    )
    .shadow(color: .black.opacity(panel ? (p.dark ? 0.22 : 0.10) : 0), radius: 12, x: 0, y: 5)
    .onContinuousHover { phase in
      guard !m.capture else { return }
      switch phase {
      case .active(let location):
        hover = true
        if !m.reduced {
          pointer = UnitPoint(
            x: min(1, max(0, location.x / 240)), y: min(1, max(0, location.y / 160)))
        }
      case .ended: hover = false
      }
    }
  }
}
extension View {
  func glass(
    radius: CGFloat = 18, panel: Bool = false, control: Bool = false, selected: Bool = false
  ) -> some View {
    modifier(Glass(radius: radius, panel: panel, control: control, selected: selected))
  }
}
struct GlassButtonStyle: ButtonStyle {
  @Environment(\.palette) var p
  @EnvironmentObject var m: AppModel
  @Environment(\.isEnabled) var enabled
  var prominent = false
  var selected = false
  var compact = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 12, weight: prominent ? .medium : .regular)).padding(
      .horizontal, compact ? 11 : 14
    ).frame(minHeight: compact ? 34 : 36)
      .foregroundStyle(prominent ? p.actionText : p.ink)
      .background { if prominent { Capsule().fill(p.action.gradient) } }
      .glass(radius: 20, control: true, selected: selected)
      .opacity(enabled ? 1 : 0.45)
      .scaleEffect(configuration.isPressed && !m.reduced ? 0.975 : 1)
      .animation(
        m.reduced ? nil : .spring(response: 0.24, dampingFraction: 0.8),
        value: configuration.isPressed)
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
