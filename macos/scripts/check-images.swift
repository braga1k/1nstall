import AppKit
import Foundation
let base=URL(fileURLWithPath:CommandLine.arguments[1])
for name in ["install-dark-monochrome.png","install-light-monochrome.png"] {
    let b=NSBitmapImageRep(data:try Data(contentsOf:base.appendingPathComponent(name)))!
    let data=b.bitmapData!, stride=b.samplesPerPixel, alphaFirst=b.bitmapFormat.contains(.alphaFirst), offset=alphaFirst ? 1:0
    var maximum=0,coloured=0
    for y in 0..<b.pixelsHigh {for x in 0..<b.pixelsWide {
        let i=y*b.bytesPerRow+x*stride+offset
        let rgb=[Int(data[i]),Int(data[i+1]),Int(data[i+2])];let difference=rgb.max()!-rgb.min()!
        maximum=max(maximum,difference);if difference>1 {coloured+=1}
    }}
    print("\(name): \(b.pixelsWide)x\(b.pixelsHigh), maximum RGB difference \(maximum), pixels >1: \(coloured)")
}
let original=URL(fileURLWithPath:CommandLine.arguments[2])
let names=["install-dark.png","install-light.png","install-dark-monochrome.png","install-light-monochrome.png"]
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1240,pixelsHigh:1800,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
NSColor(calibratedWhite:0.08,alpha:1).setFill();NSRect(x:0,y:0,width:1240,height:1800).fill()
for (i,name) in names.enumerated(){let y=1800-(i+1)*450
    for (col,url) in [original.appendingPathComponent(name),base.appendingPathComponent(name)].enumerated(){NSImage(contentsOf:url)!.draw(in:NSRect(x:col*620,y:y,width:620,height:420));let label=(col==0 ? "Windows 3.5.0":"macOS 0.1.0 preview")+" · "+name; (label as NSString).draw(at:NSPoint(x:col*620+12,y:y+426),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.white])}
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using:.png,properties:[:])!.write(to:base.appendingPathComponent("comparison.png"))
