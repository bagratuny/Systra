import SwiftUI
import AppKit

@MainActor final class WindowNavigation: ObservableObject {
    @Published var tab: MainTab = .dashboard
    @Published var search = ""
}
struct WindowBrand: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var navigation: WindowNavigation
    var body: some View {
        HStack(spacing: 8) {
            if let icon = SystraIcons.small ?? NSApp.applicationIconImage { Image(nsImage: icon).resizable().frame(width: 24, height: 24) }
            Text("Systra").font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 0)
        }.frame(width: 145, height: 40)
    }
}

struct WindowTabs: View {
    @ObservedObject var navigation: WindowNavigation
    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                strip.glassEffect(.regular, in: .capsule)
            } else {
                strip.background(.ultraThinMaterial, in: Capsule())
            }
        }.frame(width: TabSizing.railWidth(MainTab.allCases.map(\.title)), height: 44)
    }
    private var strip: some View {
        SectionTabs(tabs: MainTab.allCases, selection: $navigation.tab,
            title: { $0.title }, icon: { $0.icon }, color: { $0.color })
    }
}

// Toolbar background must not turn clicks on a tab's padding into window dragging.
final class ToolbarHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}
