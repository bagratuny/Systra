import SwiftUI
import AppKit

/// Keep native scrolling, wheel/trackpad gestures and thumb dragging, with an overlay indicator.
struct SystraScrollView<Content: View>: View {
    private let axes: Axis.Set
    private let unclipped: Bool
    private let content: Content
    init(_ axes: Axis.Set = .vertical, unclipped: Bool = false, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.unclipped = unclipped
        self.content = content()
    }
    var body: some View {
        ScrollView(axes) { content }
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .scrollClipDisabled(unclipped)
            .background(ScrollAppearanceProbe().allowsHitTesting(false).accessibilityHidden(true))
    }
}

enum SystraScrollAppearance {
    static func apply(to scroll: NSScrollView) {
        // Set only differing values so polling does not reset the native hide timer.
        if scroll.scrollerStyle != .overlay { scroll.scrollerStyle = .overlay }
        if !scroll.autohidesScrollers { scroll.autohidesScrollers = true }
        if scroll.drawsBackground { scroll.drawsBackground = false }
        scroll.borderType = .noBorder
        scroll.scrollerKnobStyle = scroll.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .light : .dark
        scroll.verticalScroller?.controlSize = .small
        scroll.horizontalScroller?.controlSize = .small
        // SwiftUI can retain a legacy-width document after switching to overlay scrollers.
        // Reclaim only that reserved gutter; intentionally narrow documents remain unchanged.
        if !scroll.hasHorizontalScroller, let document = scroll.documentView {
            let width = scroll.contentView.bounds.width
            let gap = width - document.frame.width
            let gutter = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            if gap > 0.5 && abs(gap - gutter) <= 1 {
                document.autoresizingMask.insert(.width)
                document.setFrameSize(NSSize(width: width, height: document.frame.height))
            }
        }
    }
}
struct ScrollAppearanceProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView { ProbeView() }
    func updateNSView(_ view: ProbeView, context: Context) { view.scheduleAppearance() }

    final class ProbeView: NSView {
        private var scheduled = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleAppearance()
        }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            scheduleAppearance()
        }
        func scheduleAppearance() {
            guard !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scheduled = false
                guard self.window != nil else { return }
                func scrolls(in node: NSView) -> [NSScrollView] {
                    let own = (node as? NSScrollView).map { [$0] } ?? []
                    return own + node.subviews.flatMap { scrolls(in: $0) }
                }
                var ancestor = self.superview
                while let node = ancestor {
                    let found = scrolls(in: node)
                    if !found.isEmpty {
                        found.forEach { SystraScrollAppearance.apply(to: $0) }
                        return
                    }
                    ancestor = node.superview
                }
            }
        }
    }
}
