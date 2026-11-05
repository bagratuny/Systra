import SwiftUI
import AppKit

/// Shared, neutral instrument-panel surfaces. Metric colours belong to the data.
enum InstrumentStyle {
    static let canvas = adaptive(dark: 0x1B1C1E, light: 0xF5F5F6)
    static let surface = adaptive(dark: 0x242528, light: 0xFFFFFF)
    static let raised = adaptive(dark: 0x2D2F33, light: 0xEDEEF0)
    private static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }
}
extension View {
    func instrumentSurface(radius: CGFloat = 12) -> some View {
        background(InstrumentStyle.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.primary.opacity(0.07), lineWidth: 0.5))
    }
}
struct InstrumentCardButtonStyle: ButtonStyle {
    let tint: Color
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(configuration.isPressed || hovered ? InstrumentStyle.raised : InstrumentStyle.surface)
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(configuration.isPressed ? 0.12 : hovered ? 0.09 : 0.065))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(hovered ? 0.40 : 0.22), lineWidth: 1))
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.16), value: hovered)
    }
}
struct LiveUpdateLabel: View {
    @ObservedObject var monitor: Monitor
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(monitor.error != nil || monitor.updated == nil ? Color.orange : Color.mint).frame(width: 4, height: 4)
            Text(monitor.updated.map { L("Данные · ") + $0.formatted(Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits).locale(AppLanguage.current.locale)) } ?? L("Ожидание данных"))
                .monospacedDigit()
        }.font(.system(size: 11)).foregroundStyle(.secondary)
            .help(L("Время последнего полученного замера. Обновление каждые 2 секунды"))
    }
}
