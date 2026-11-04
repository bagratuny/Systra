import AppKit
import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func makeIcon(_ pointSize: Int, scale: Int = 1) -> Data {
    let size = pointSize * scale
    let miniature = pointSize <= 32
    let small = pointSize <= 64
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let tile = NSBezierPath(roundedRect: NSRect(x: 82, y: 82, width: 860, height: 860), xRadius: 198, yRadius: 198)
    context.saveGState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.28); shadow.shadowBlurRadius = small ? 12 : 30; shadow.shadowOffset = NSSize(width: 0, height: -10); shadow.set()
    NSColor(calibratedRed: 0.12, green: 0.57, blue: 0.61, alpha: 1).setFill(); tile.fill()
    context.restoreGState()
    NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.58, blue: 0.64, alpha: 1), NSColor(calibratedRed: 0.38, green: 0.81, blue: 0.79, alpha: 1), NSColor(calibratedRed: 0.78, green: 0.96, blue: 0.92, alpha: 1)])!.draw(in: tile, angle: 65)
    if !small { NSColor.white.withAlphaComponent(0.35).setStroke(); tile.lineWidth = 3; tile.stroke() }
    context.saveGState()
    context.translateBy(x: 512, y: 510)
    context.rotate(by: -0.48)
    let feather = NSBezierPath()
    if small {
        // Optical miniature: broader silhouette, fewer cuts and a stronger central vein.
        context.scaleBy(x: miniature ? 1.3 : 1.18, y: 1.05)
        feather.move(to: NSPoint(x: 0, y: 325))
        feather.curve(to: NSPoint(x: 175, y: 70), controlPoint1: NSPoint(x: 160, y: 295), controlPoint2: NSPoint(x: 205, y: 190))
        if !miniature {
            feather.line(to: NSPoint(x: 80, y: 30)); feather.line(to: NSPoint(x: 164, y: 40))
        }
        feather.curve(to: NSPoint(x: 0, y: -242), controlPoint1: NSPoint(x: 165, y: -120), controlPoint2: NSPoint(x: 55, y: -220))
        feather.curve(to: NSPoint(x: -162, y: 40), controlPoint1: NSPoint(x: -110, y: -230), controlPoint2: NSPoint(x: -195, y: -80))
        feather.curve(to: NSPoint(x: 0, y: 325), controlPoint1: NSPoint(x: -155, y: 190), controlPoint2: NSPoint(x: -65, y: 285))
    } else {
    feather.move(to: NSPoint(x: 0, y: 325))
    feather.curve(to: NSPoint(x: 187, y: 125), controlPoint1: NSPoint(x: 150, y: 285), controlPoint2: NSPoint(x: 207, y: 220))
    feather.line(to: NSPoint(x: 83, y: 70)); feather.line(to: NSPoint(x: 183, y: 95))
    feather.curve(to: NSPoint(x: 142, y: -73), controlPoint1: NSPoint(x: 184, y: 35), controlPoint2: NSPoint(x: 172, y: -32))
    feather.line(to: NSPoint(x: 65, y: -98)); feather.line(to: NSPoint(x: 122, y: -108))
    feather.curve(to: NSPoint(x: 0, y: -242), controlPoint1: NSPoint(x: 85, y: -180), controlPoint2: NSPoint(x: 32, y: -222))
    feather.curve(to: NSPoint(x: -160, y: -92), controlPoint1: NSPoint(x: -76, y: -210), controlPoint2: NSPoint(x: -151, y: -154))
    feather.line(to: NSPoint(x: -70, y: -66)); feather.line(to: NSPoint(x: -174, y: -61))
    feather.curve(to: NSPoint(x: -164, y: 80), controlPoint1: NSPoint(x: -190, y: -11), controlPoint2: NSPoint(x: -181, y: 44))
    feather.line(to: NSPoint(x: -68, y: 126)); feather.line(to: NSPoint(x: -148, y: 115))
    feather.curve(to: NSPoint(x: 0, y: 325), controlPoint1: NSPoint(x: -113, y: 234), controlPoint2: NSPoint(x: -42, y: 292))
    }
    feather.close()
    context.saveGState()
    let featherShadow = NSShadow(); featherShadow.shadowColor = NSColor(calibratedRed: 0.03, green: 0.30, blue: 0.35, alpha: small ? 0 : 0.24); featherShadow.shadowBlurRadius = small ? 0 : 22; featherShadow.shadowOffset = NSSize(width: -5, height: -14); featherShadow.set()
    NSColor.white.setFill(); feather.fill()
    context.restoreGState()
    NSGradient(colors: [.white, NSColor(calibratedRed: 0.86, green: 0.99, blue: 0.96, alpha: 1)])!.draw(in: feather, angle: 0)
    let vein = NSBezierPath()
    if miniature {
        vein.move(to: NSPoint(x: 0, y: -310)); vein.line(to: NSPoint(x: 0, y: -60))
        vein.line(to: NSPoint(x: -34, y: -10)); vein.line(to: NSPoint(x: 34, y: 45))
        vein.line(to: NSPoint(x: 0, y: 100)); vein.line(to: NSPoint(x: 0, y: 235))
    } else {
    vein.move(to: NSPoint(x: 0, y: -325)); vein.line(to: NSPoint(x: 0, y: -89))
    vein.line(to: NSPoint(x: -40, y: -40)); vein.line(to: NSPoint(x: 48, y: 16))
    vein.line(to: NSPoint(x: -34, y: 70)); vein.line(to: NSPoint(x: 0, y: 110)); vein.line(to: NSPoint(x: 0, y: 244))
    }
    vein.lineCapStyle = .round; vein.lineJoinStyle = .round; vein.lineWidth = miniature ? 48 : (small ? 35 : 25)
    NSColor(calibratedRed: 0.06, green: 0.51, blue: 0.56, alpha: 1).setStroke(); vein.stroke()
    context.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for pointSize in [16, 32, 128, 256, 512] {
    for scale in [1,2] {
        let name = "icon_\(pointSize)x\(pointSize)\(scale == 2 ? "@2x" : "").png"
        try makeIcon(pointSize, scale: scale).write(to: directory.appendingPathComponent(name))
    }
}

// Explicit miniature for SwiftUI surfaces that otherwise resample the 1024px representation.
try makeIcon(28, scale: 2).write(to: directory.deletingLastPathComponent().appendingPathComponent("SystraSmall.png"))
