import AppKit
import SwiftUI

/// A fixed outer rail with a single moving selection. Only the tabs' internal layout changes.
struct SectionTabs<Tab: Hashable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String
    let icon: (Tab) -> String
    let color: (Tab) -> Color
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation? {
        reduceMotion || !settings.animations ? nil : .spring(response: 0.34, dampingFraction: 0.9)
    }
    var body: some View {
        GeometryReader { viewport in
            let index = tabs.firstIndex(of: selection) ?? 0
            let titles = tabs.map(title)
            let layout = TabRailGeometry(width: max(0, viewport.size.width - 8),
                count: tabs.count, selectedIndex: index,
                preferredSelectionWidth: TabSizing.selectedWidth(titles[index]))
            ZStack(alignment: .leading) {
                Capsule().fill(color(selection).opacity(0.22))
                    .overlay(Capsule().strokeBorder(.primary.opacity(0.04), lineWidth: 0.5))
                    .frame(width: layout.selectedWidth, height: 36)
                    .offset(x: layout.selectedOffset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                HStack(spacing: TabRailGeometry.spacing) {
                    ForEach(tabs, id: \.self) { tab in
                        let selected = tab == selection
                        Button { selection = tab } label: {
                            HStack(spacing: selected ? 8 : 0) {
                                Image(systemName: icon(tab))
                                    .font(.system(size: 16, weight: .medium)).frame(width: 18)
                                // Keep the label alive while its space closes; clipping prevents
                                // outgoing text from drawing over neighbouring icons.
                                Text(title(tab)).font(.system(size: 12, weight: .medium)).fixedSize()
                                    .opacity(selected ? 1 : 0)
                                    .animation(motion == nil ? nil : .easeOut(duration: 0.14), value: selected)
                                    .frame(width: selected ? max(0, layout.selectedWidth - 52) : 0, alignment: .leading)
                                    .clipped()
                            }
                            .foregroundStyle(selected ? color(tab) : Color.secondary)
                            .frame(width: selected ? layout.selectedWidth : layout.inactiveWidth, height: 36)
                            .contentShape(.interaction, Rectangle())
                        }
                        .buttonStyle(SectionTabButtonStyle(selected: selected, animated: motion != nil))
                        .help(title(tab))
                        .accessibilityLabel(L("Вкладка {0}", title(tab)))
                        .accessibilityValue(selected ? L("Выбрана") : "")
                    }
                }
            }
            .frame(width: layout.width, height: 36, alignment: .leading)
            .padding(4)
            // The page binding changes outside this transaction: charts and tables do not animate.
            .animation(motion, value: selection)
        }.frame(height: 44)
    }
}

private struct SectionTabButtonStyle: ButtonStyle {
    let selected: Bool
    let animated: Bool
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Capsule().fill(.primary.opacity(configuration.isPressed ? 0.09 : hovered && !selected ? 0.055 : 0))
            }
            .onHover { hovered = $0 }
            .animation(animated ? .easeOut(duration: 0.12) : nil, value: hovered)
            .animation(animated ? .easeOut(duration: 0.08) : nil, value: configuration.isPressed)
    }
}

enum TabSizing {
    static func selectedWidth(_ title: String) -> CGFloat {
        ceil((title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width) + 52
    }
    static func railWidth(_ titles: [String]) -> CGFloat {
        let inactiveCount = max(0, titles.count - 1)
        return (titles.map(selectedWidth).max() ?? 44) + CGFloat(inactiveCount) * (44 + TabRailGeometry.spacing) + 8
    }
}
