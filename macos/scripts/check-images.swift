import AppKit
import Foundation

let base = URL(fileURLWithPath: CommandLine.arguments[1])
let original = URL(fileURLWithPath: CommandLine.arguments[2])
let previous =
  CommandLine.arguments.count > 3 ? URL(fileURLWithPath: CommandLine.arguments[3]) : nil
let images = try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
var failures = 0
let monochrome = images.filter {
  $0.lastPathComponent.contains("monochrome") && $0.pathExtension == "png"
}
for url in monochrome.sorted(by: { $0.path < $1.path }) {
  let b = NSBitmapImageRep(data: try Data(contentsOf: url))!
  let data = b.bitmapData!
  let stride = b.samplesPerPixel
  let offset = b.bitmapFormat.contains(.alphaFirst) ? 1 : 0
  var maximum = 0
  var coloured = 0
  for y in 0..<b.pixelsHigh {
    for x in 0..<b.pixelsWide {
      let i = y * b.bytesPerRow + x * stride + offset
      let rgb = [Int(data[i]), Int(data[i + 1]), Int(data[i + 2])]
      let difference = rgb.max()! - rgb.min()!
      maximum = max(maximum, difference)
      if difference > 1 { coloured += 1 }
    }
  }
  if coloured > 0 { failures += 1 }
  print(
    "\(url.lastPathComponent): \(b.pixelsWide)x\(b.pixelsHigh), maximum RGB difference \(maximum), pixels >1: \(coloured)"
  )
}
if monochrome.count != 6 {
  print("Expected six monochrome views")
  failures += 1
}
let names = [
  "install-dark.png", "install-light.png", "install-dark-monochrome.png",
  "install-light-monochrome.png",
]
let columns = previous == nil ? 2 : 3
let bitmap = NSBitmapImageRep(
  bitmapDataPlanes: nil, pixelsWide: 620 * columns, pixelsHigh: 1800, bitsPerSample: 8,
  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
  bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 620 * columns, height: 1800).fill()
for (i, name) in names.enumerated() {
  let y = 1800 - (i + 1) * 450
  var sources = [("Windows 3.5.0", original)]
  if let previous { sources.append(("macOS 0.2.0", previous)) }
  sources.append(("macOS 0.2.1", base))
  for (col, source) in sources.enumerated() {
    NSImage(contentsOf: source.1.appendingPathComponent(name))!.draw(
      in: NSRect(x: col * 620, y: y, width: 620, height: 420))
    (source.0 + " · " + name as NSString).draw(
      at: NSPoint(x: col * 620 + 12, y: y + 426),
      withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white])
  }
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(
  to: base.appendingPathComponent("comparison.png"))
// Separate comparison for the explicitly requested Windows-style Uninstall list.
let removal = NSBitmapImageRep(
  bitmapDataPlanes: nil, pixelsWide: 1240, pixelsHigh: 450, bitsPerSample: 8,
  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
  bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: removal)
NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 1240, height: 450).fill()
for (column, source) in [("Windows 3.5.0", original), ("macOS 0.2.1", base)].enumerated() {
  NSImage(contentsOf: source.1.appendingPathComponent("uninstall-dark.png"))!.draw(
    in: NSRect(x: column * 620, y: 0, width: 620, height: 420))
  (source.0 + " · Uninstall" as NSString).draw(
    at: NSPoint(x: column * 620 + 12, y: 426),
    withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white])
}
NSGraphicsContext.restoreGraphicsState()
try removal.representation(using: .png, properties: [:])!.write(
  to: base.appendingPathComponent("uninstall-comparison.png"))
print("\(monochrome.count) monochrome images checked; \(failures) failures")
exit(failures == 0 ? 0 : 1)
