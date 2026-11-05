import SwiftUI

struct SystemUptimeTile: View {
    let snapshot: SystemUptimeSnapshot
    let action: () -> Void
    var body: some View {
        OverviewCard(tab: .dashboard, title: L("Аптайм системы"), metricColor: .teal, value: snapshot.bootDate == nil ? "—" : uptimeDuration(snapshot.includingSleep, compact: true), detail: L("С последней загрузки\nВключая сон"), action: action)
            .accessibilityLabel(L("Аптайм системы, ") + uptimeDuration(snapshot.includingSleep))
            .help(L("Аптайм, загрузка системы, время без сна, пробуждения и сведения о Mac"))
    }
}

struct UptimeDetailsView: View {
    @ObservedObject var monitor: Monitor
    @Environment(\.dismiss) private var dismiss
    private var uptime: SystemUptimeSnapshot { monitor.hardware.uptime }
    private let info = SystemInformation.current
    private func timestamp(_ value: Date?) -> String {
        value?.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(AppLanguage.current.locale)) ?? L("Недоступно")
    }
    private func item(_ title: String, _ value: String, help: String? = nil) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 20)
            Text(value).multilineTextAlignment(.trailing).monospacedDigit().textSelection(.enabled)
        }.font(.system(size: 12)).padding(.vertical, 4).help(help ?? title)
    }
    private func duration(_ title: String, _ seconds: Double, color: Color, help: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
            Text(uptimeDuration(seconds)).font(.system(size: 17, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .instrumentSurface().help(help)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(L("Аптайм системы"), systemImage: "clock.arrow.circlepath").font(.title2.weight(.medium))
                Spacer()
                Button(L("Готово")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            SystraScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    duration(L("С последней загрузки · включая сон"), uptime.includingSleep, color: .teal, help: L("Непрерывный монотонный счётчик с загрузки системы, включающий сон. Не зависит от перевода календарных часов."))
                    HStack(spacing: 8) {
                        duration(L("Без сна"), uptime.awake, color: .mint, help: L("Время работы системы без сна. Это не время активности пользователя: простой Mac тоже учитывается."))
                        duration(L("Во сне · суммарно"), uptime.sleeping, color: .indigo, help: L("Расчётная разница между счётчиками с учётом сна и без сна. Фоновые пробуждения могут учитываться как работа системы."))
                    }
                    ProgressView(value: uptime.awakeFraction).tint(.mint)
                    Text(L("Без сна: {0} · во сне: {1}", String(describing: percent(uptime.awakeFraction * 100)), String(describing: percent((1 - uptime.awakeFraction) * 100)))).font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Загрузка и пробуждения")).font(.headline)
                        item(L("Последняя загрузка"), timestamp(uptime.bootDate))
                        item(L("Часовой пояс"), TimeZone.current.identifier)
                        item(L("Переходы в сон"), uptime.power.sleep.map(String.init) ?? "—", help: L("Системный счётчик Sleep Count из pmset. Обновляется примерно раз в минуту."))
                        item(L("Фоновые пробуждения"), uptime.power.darkWake.map(String.init) ?? "—", help: L("Dark Wake Count из pmset: пробуждения для фоновых задач, которые могут происходить без включения экрана."))
                        item(L("Обычные пробуждения"), uptime.power.userWake.map(String.init) ?? "—", help: L("User Wake Count из pmset. Это счётчик системы, а не число входов пользователя."))
                        item(L("Последнее пробуждение при Systra"), monitor.lastWakeDate.map { timestamp($0) } ?? L("Пока не наблюдалось"))
                        item(L("Последний переход в сон при Systra"), monitor.lastSleepDate.map { timestamp($0) } ?? L("Пока не наблюдалось"))
                        Text(L("Последние события отслеживаются только с запуска Systra. Системные счётчики сна обновляются раз в минуту; они не являются историей перезагрузок.")).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Система")).font(.headline)
                        item("macOS", L("{0} · сборка {1}", String(describing: info.osVersion), String(describing: info.build)))
                        item(L("Ядро Darwin"), info.kernel)
                        item(L("Модель Mac"), info.model)
                        item(L("Чип"), info.chip)
                        item(L("Логические ядра / RAM"), "\(ProcessInfo.processInfo.activeProcessorCount) / \(bytes(monitor.totalMemory))")
                        item(L("Load Average · 1 / 5 / 15 мин"), uptime.load.isEmpty ? "—" : uptime.load.map { decimal($0, digits: 2) }.joined(separator: " / "), help: L("Средняя системная нагрузка за 1, 5 и 15 минут. Это не проценты CPU; оценивай относительно количества логических ядер."))
                        item(L("Systra запущен"), timestamp(monitor.sessionStartedAt))
                        item(L("Текущий сеанс Systra"), uptimeDuration(max(0, uptime.includingSleep - monitor.sessionStartClock)))
                    }
                }.padding(.trailing, 5)
            }
        }.padding(20).frame(width: 650, height: 660)
    }
}
