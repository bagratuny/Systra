import AppKit
import SwiftUI

@MainActor final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "systra.language"); changed() }
    }
    @Published var appearance: String {
        didSet { UserDefaults.standard.set(appearance, forKey: "systra.appearance"); applyAppearance(); changed() }
    }
    @Published var menuMetrics: Set<MenuBarMetric> {
        didSet { UserDefaults.standard.set(MenuBarMetric.encoded(menuMetrics), forKey: "systra.menuMetrics"); changed() }
    }
    @Published var animations: Bool {
        didSet { UserDefaults.standard.set(animations, forKey: "systra.animations"); changed() }
    }
    static let didChange = Notification.Name("Systra.SettingsChanged")
    private init() {
        let defaults = UserDefaults.standard
        language = .current
        appearance = defaults.string(forKey: "systra.appearance") ?? "system"
        menuMetrics = MenuBarMetric.load(from: defaults)
        animations = defaults.object(forKey: "systra.animations") as? Bool ?? true
    }
    func applyAppearance() {
        NSApp.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua) : appearance == "light" ? NSAppearance(named: .aqua) : nil
    }
    private func changed() {
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

/// Rebuild language-dependent view state without replacing the monitor or navigation.
struct LocalizedRoot<Content: View>: View {
    @ObservedObject private var settings = AppSettings.shared
    @ViewBuilder let content: () -> Content
    var body: some View {
        content().id(settings.language).environment(\.locale, settings.language.locale)
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var login = LoginItemSettings.shared
    @ObservedObject var monitor: Monitor
    var body: some View {
        TabView {
            general.tabItem { Text(L("Основные")) }
            menuBar.tabItem { Text(L("Строка меню")) }
        }.padding(12).frame(width: 520, height: 560)
            .background(ScrollAppearanceProbe().allowsHitTesting(false).accessibilityHidden(true))
            .onAppear { login.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
    }
    private var general: some View {
        Form {
            Section {
                Picker(L("Язык"), selection: $settings.language) {
                    Text("Русский").tag(AppLanguage.russian)
                    Text("English").tag(AppLanguage.english)
                }
                Text(L("Язык меняется сразу во всех окнах и меню.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Интерфейс")) {
                Picker(L("Оформление"), selection: $settings.appearance) {
                    Text(L("Как в системе")).tag("system")
                    Text(L("Светлое")).tag("light")
                    Text(L("Тёмное")).tag("dark")
                }
                Toggle(L("Анимации вкладок"), isOn: $settings.animations)
                Text(L("Учитывается системная настройка уменьшения движения.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Автозапуск")) {
                Toggle(L("Запускать при входе в macOS"), isOn: Binding(get: { login.isRequested }, set: { login.setEnabled($0) }))
                if login.state == .requiresApproval {
                    Text(L("Разреши автозапуск Systra в системных настройках → Основные → Объекты входа.")).font(.caption).foregroundStyle(.secondary)
                    Button(L("Открыть объекты входа…")) { login.openSystemSettings() }
                } else {
                    Text(login.state == .enabled ? L("Автозапуск включён.") : L("Systra будет открываться при входе в систему.")).font(.caption).foregroundStyle(.secondary)
                }
                if let error = login.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                if login.state == .unavailable {
                    Text(L("macOS не удалось определить состояние автозапуска.")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Text(L("Показатели обновляются каждые 2 секунды. После закрытия окна мониторинг продолжает работать в строке меню."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var menuBar: some View {
        Form {
            Section(L("Предпросмотр")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        Image(nsImage: systraMenuBarIcon()).frame(width: 20, height: 20)
                        Text(monitor.menuBarReadings.text(for: settings.menuMetrics))
                            .font(.system(size: 12, weight: .medium)).monospacedDigit().fixedSize()
                    }.padding(.vertical, 4)
                }
            }
            Section(L("Показатели рядом с иконкой")) {
                ForEach(MenuBarMetric.allCases) { metric in
                    Toggle(metric.title, isOn: Binding(get: { settings.menuMetrics.contains(metric) }, set: { selected in
                        if selected { settings.menuMetrics.insert(metric) }
                        else { settings.menuMetrics.remove(metric) }
                    }))
                }
            }
            Section {
                Button(L("Только иконка")) { settings.menuMetrics = [] }.disabled(settings.menuMetrics.isEmpty)
                Text(L("Можно выбрать несколько показателей. Чем их больше, тем больше места занимает Systra в строке меню."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
