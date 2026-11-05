import AppKit
import SwiftUI
import Foundation

// ICNS does not apply the system icon mask to a full-bleed bitmap.
// Clip the background to a macOS tile independently from the artwork scale.
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        guard let source = NSImage(contentsOf: input.appendingPathComponent(filename)) else { fatalError("Missing \(filename)") }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let context = NSGraphicsContext.current!.cgContext
        context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.current!.imageInterpolation = .high
        let inset = max(1, (CGFloat(pixels) * 0.10).rounded(.toNearestOrAwayFromZero))
        let bounds = NSRect(x: inset, y: inset, width: CGFloat(pixels) - 2 * inset, height: CGFloat(pixels) - 2 * inset)
        let radius = bounds.width * 0.225
        let contour = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: bounds)
        context.addPath(contour.cgPath)
        context.clip()
        // Retain the original 84% artwork size; trim only the background outside the tile.
        let artworkInset = max(1, (CGFloat(pixels) * 0.08).rounded(.toNearestOrAwayFromZero))
        let artwork = NSRect(x: artworkInset, y: artworkInset, width: CGFloat(pixels) - 2 * artworkInset, height: CGFloat(pixels) - 2 * artworkInset)
        source.draw(in: artwork, from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        // All sizes must retain real transparency, rather than painting corner colours.
        for (x, y) in [(0, 0), (pixels - 1, 0), (0, pixels - 1), (pixels - 1, pixels - 1)] {
            precondition(rep.colorAt(x: x, y: y)!.alphaComponent == 0)
        }
        precondition(rep.colorAt(x: pixels / 2, y: pixels / 2)!.alphaComponent > 0.99)
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
    }
}
print("Prepared 10 rounded app icon representations")
