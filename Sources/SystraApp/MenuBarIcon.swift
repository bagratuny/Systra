import AppKit

func featherMenuBarIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
        NSColor.black.setFill()
        let feather = NSBezierPath()
        feather.move(to: NSPoint(x: 4, y: 4))
        feather.curve(to: NSPoint(x: 17.5, y: 18), controlPoint1: NSPoint(x: 1, y: 12), controlPoint2: NSPoint(x: 10, y: 19))
        feather.curve(to: NSPoint(x: 7, y: 5), controlPoint1: NSPoint(x: 19, y: 10), controlPoint2: NSPoint(x: 13, y: 5))
        feather.line(to: NSPoint(x: 10, y: 9))
        feather.line(to: NSPoint(x: 6.5, y: 7))
        feather.close()
        feather.fill()
        let quill = NSBezierPath()
        quill.move(to: NSPoint(x: 2.5, y: 1.5))
        quill.line(to: NSPoint(x: 6, y: 6))
        quill.lineWidth = 1.5
        quill.lineCapStyle = .round
        quill.stroke()
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Systra — перо"
    return image
}

@MainActor enum SystraIcons {
    static let small: NSImage? = {
        guard let url = Bundle.main.url(forResource: "SystraSmall", withExtension: "png"), let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 28, height: 28)
        return image
    }()
}
