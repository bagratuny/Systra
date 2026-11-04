import SwiftUI

struct SystemUptimeTile: View {
    let snapshot: SystemUptimeSnapshot
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Аптайм системы", systemImage: "clock.arrow.circlepath").font(.system(size: 12, weight: .semibold)).foregroundStyle(.teal)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                HStack {
                    Text(snapshot.bootDate == nil ? "—" : uptimeDuration(snapshot.includingSleep, compact: true)).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    Spacer()
                    Image(systemName: "power").font(.system(size: 25)).foregroundStyle(.teal.opacity(0.6)).frame(width: 45, height: 37)
                }
                Text("С последней загрузки · включая сон\nНажми для подробной сводки").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).frame(height: 29, alignment: .topLeading)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.teal.opacity(0.065), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.teal.opacity(0.12)))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }.buttonStyle(.plain).help("Аптайм, загрузка системы, время без сна, пробуждения и сведения о Mac")
    }
}

struct UptimeDetailsView: View {
    @ObservedObject var monitor: Monitor
    @Environment(\.dismiss) private var dismiss
    private var uptime: SystemUptimeSnapshot { monitor.hardware.uptime }
    private let info = SystemInformation.current
    private func timestamp(_ value: Date?) -> String {
        value?.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(Locale(identifier: "ru_RU"))) ?? "Недоступно"
    }
    private func item(_ title: String, _ value: String, help: String? = nil) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 20)
            Text(value).multilineTextAlignment(.trailing).monospacedDigit().textSelection(.enabled)
        }.font(.system(size: 12)).padding(.vertical, 4).help(help ?? title)
    }
    private func duration(_ title: String, _ seconds: Double, color: Color, help: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            Text(uptimeDuration(seconds)).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous)).help(help)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Аптайм системы", systemImage: "clock.arrow.circlepath").font(.title2.bold())
                Spacer()
                Button("Готово") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    duration("С последней загрузки · включая сон", uptime.includingSleep, color: .teal, help: "Непрерывный монотонный счётчик с загрузки системы, включающий сон. Не зависит от перевода календарных часов.")
                    HStack(spacing: 8) {
                        duration("Без сна", uptime.awake, color: .mint, help: "Время работы системы без сна. Это не время активности пользователя: простой Mac тоже учитывается.")
                        duration("Во сне · суммарно", uptime.sleeping, color: .indigo, help: "Расчётная разница между счётчиками с учётом сна и без сна. Фоновые пробуждения могут учитываться как работа системы.")
                    }
                    ProgressView(value: uptime.awakeFraction).tint(.mint)
                    Text(String(format: "Без сна: %.1f%% · во сне: %.1f%%", uptime.awakeFraction * 100, (1 - uptime.awakeFraction) * 100)).font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Загрузка и пробуждения").font(.headline)
                        item("Последняя загрузка", timestamp(uptime.bootDate))
                        item("Часовой пояс", TimeZone.current.identifier)
                        item("Переходы в сон", uptime.power.sleep.map(String.init) ?? "—", help: "Системный счётчик Sleep Count из pmset. Обновляется примерно раз в минуту.")
                        item("Фоновые пробуждения", uptime.power.darkWake.map(String.init) ?? "—", help: "Dark Wake Count из pmset: пробуждения для фоновых задач, которые могут происходить без включения экрана.")
                        item("Обычные пробуждения", uptime.power.userWake.map(String.init) ?? "—", help: "User Wake Count из pmset. Это счётчик системы, а не число входов пользователя.")
                        item("Последнее пробуждение при Systra", monitor.lastWakeDate.map { timestamp($0) } ?? "Пока не наблюдалось")
                        item("Последний переход в сон при Systra", monitor.lastSleepDate.map { timestamp($0) } ?? "Пока не наблюдалось")
                        Text("Последние события отслеживаются только с запуска Systra. Системные счётчики сна обновляются раз в минуту; они не являются историей перезагрузок.").font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Система").font(.headline)
                        item("macOS", "\(info.osVersion) · сборка \(info.build)")
                        item("Ядро Darwin", info.kernel)
                        item("Модель Mac", info.model)
                        item("Чип", info.chip)
                        item("Логические ядра / RAM", "\(ProcessInfo.processInfo.activeProcessorCount) / \(bytes(monitor.totalMemory))")
                        item("Load Average · 1 / 5 / 15 мин", uptime.load.isEmpty ? "—" : uptime.load.map { String(format: "%.2f", $0) }.joined(separator: " / "), help: "Средняя системная нагрузка за 1, 5 и 15 минут. Это не проценты CPU; оценивай относительно количества логических ядер.")
                        item("Systra запущен", timestamp(monitor.sessionStartedAt))
                        item("Текущий сеанс Systra", uptimeDuration(max(0, uptime.includingSleep - monitor.sessionStartClock)))
                    }
                }.padding(.trailing, 5)
            }
        }.padding(20).frame(width: 650, height: 660)
    }
}
