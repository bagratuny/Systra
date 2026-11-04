import AppKit

func systraMenuBarIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 20, height: 20))
    // Keep the 20 pt status-item canvas; only the visible mark becomes 16 pt.
    for (scale, name) in [(1, "SystraMenu"), (2, "SystraMenu@2x")] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"), let source = NSImage(contentsOf: url) else { continue }
        let pixels = 20 * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let context = NSGraphicsContext.current!.cgContext
        context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        NSGraphicsContext.current!.imageInterpolation = .high
        source.draw(in: NSRect(x: 2, y: 2, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        rep.size = NSSize(width: 20, height: 20)
        image.addRepresentation(rep)
    }
    image.isTemplate = true
    image.accessibilityDescription = "Systra"
    return image
}
@MainActor enum SystraIcons {
    static let small: NSImage? = {
        guard let url = Bundle.main.url(forResource: "SystraSmall", withExtension: "png"), let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 32, height: 32)
        return image
    }()
}
