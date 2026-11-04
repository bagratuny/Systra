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
        HStack(spacing: 7) {
            if let icon = SystraIcons.small ?? NSApp.applicationIconImage { Image(nsImage: icon).resizable().frame(width: 25, height: 25) }
            VStack(alignment: .leading, spacing: 2) {
                Text("Systra").font(.system(size: 13, weight: .bold))
                Text("\(navigation.tab.title) · \(monitor.hardware.gpuName)").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }.frame(width: 145, height: 40)
    }
}

struct WindowTabs: View {
    @ObservedObject var navigation: WindowNavigation
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var strip: some View {
        HStack(spacing: 2) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button { navigation.tab = tab } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(navigation.tab == tab ? tab.color : Color.secondary)
                        .frame(width: 44, height: 34)
                        .background {
                            if navigation.tab == tab {
                                Capsule().fill(tab.color.opacity(0.30))
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
                                    .matchedGeometryEffect(id: "selected-tab", in: selection)
                            }
                        }
                        .contentShape(.interaction, Rectangle())
                }.buttonStyle(.plain).help(tab.title)
                    .accessibilityLabel("Вкладка \(tab.title)")
                    .accessibilityValue(navigation.tab == tab ? "Выбрана" : "")
            }
        }.padding(3)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: navigation.tab)
    }
    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                strip.glassEffect(.regular, in: .capsule)
            } else {
                strip.background(.ultraThinMaterial, in: Capsule())
            }
        }.frame(width: 372, height: 40)
    }
}

// Toolbar background must not turn clicks on a tab's padding into window dragging.
final class ToolbarHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}
