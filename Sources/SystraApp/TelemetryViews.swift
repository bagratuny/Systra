import SwiftUI

struct TelemetryTile: View {
    let title: String
    let symbol: String
    let value: String
    let detail: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 21, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2).frame(height: 28, alignment: .topLeading)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .instrumentSurface()
    }
}
struct SensorList: View {
    @ObservedObject var monitor: Monitor
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Температурные датчики")).font(.title2.weight(.medium))
            Text(L("Показания сгруппированы по компонентам. Справа — самое высокое показание группы. Названия macOS доступны при наведении на отдельный датчик."))
                .font(.caption).foregroundStyle(.secondary)
            SystraScrollView { TemperatureGroupsView(readings: monitor.hardware.temperatures, compact: true) }
        }.padding(24).frame(width: 440, height: 490)
    }
}
struct HardwareTiles: View {
    @ObservedObject var monitor: Monitor
    @State private var sensors = false
    var storageDetail: String {
        if let free = monitor.hardware.diskFree, let total = monitor.hardware.diskTotal { return L("Свободно {0} из {1}", String(describing: bytes(free)), String(describing: bytes(total))) }
        return L("Том пользователя недоступен")
    }
    var body: some View {
        HStack(spacing: 12) {
            TelemetryTile(title: L("Диск"), symbol: "internaldrive", value: "↓ \(rate(monitor.diskRead))", detail: L("↑ {0} · запись\n", String(describing: rate(monitor.diskWrite))) + storageDetail, tint: .orange)
            TelemetryTile(title: L("Сеть"), symbol: "network", value: "↓ \(rate(monitor.download))", detail: L("↑ {0} · отдача\nWi-Fi / Ethernet", String(describing: rate(monitor.upload))), tint: .cyan)
            TelemetryTile(title: "GPU", symbol: "square.3.layers.3d", value: percent(monitor.hardware.gpu), detail: monitor.hardware.gpuName + "\n" + (monitor.hardware.gpuMemory.map { bytes($0) + L(" · память драйвера") } ?? L("Память недоступна")), tint: .purple)
            Button { sensors = true } label: {
                TelemetryTile(title: L("Температуры ›"), symbol: "thermometer.medium", value: degrees(monitor.chipTemperature), detail: L("Чип · максимум датчиков\nБатарея: {0}", String(describing: degrees(monitor.batteryTemperature))), tint: .pink)
            }.buttonStyle(.plain).help(L("Показать все температурные датчики"))
        }.sheet(isPresented: $sensors) {
            VStack(spacing: 0) {
                SensorList(monitor: monitor)
                Button(L("Готово")) { sensors = false }.keyboardShortcut(.defaultAction).padding(.bottom, 16)
            }
        }
    }
}
enum MetricTab: String, CaseIterable {
    case overview, cpu, memory, disk, network, gpu, temperature
    var title: String {
        switch self { case .overview: return L("Обзор"); case .cpu: return L("Процессор"); case .memory: return L("Память"); case .disk: return L("Диск"); case .network: return L("Сеть"); case .gpu: return "GPU"; case .temperature: return L("Температуры") }
    }
    var icon: String {
        switch self { case .overview: return "square.grid.2x2.fill"; case .cpu: return "cpu"; case .memory: return "memorychip.fill"; case .disk: return "internaldrive.fill"; case .network: return "network"; case .gpu: return "square.3.layers.3d"; case .temperature: return "thermometer.medium" }
    }
    var color: Color {
        switch self { case .overview, .cpu: return .mint; case .memory: return Color(red: 0.61, green: 0.53, blue: 0.95); case .disk: return .orange; case .network: return .cyan; case .gpu: return .purple; case .temperature: return .pink }
    }
}
struct MiniChart: View {
    let samples: [Sample]
    let maximum: Double
    let color: Color
    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }
            var path = Path()
            let maxValue = max(1, maximum)
            for (index, sample) in samples.enumerated() {
                let point = CGPoint(x: size.width * Double(index) / Double(max(1, samples.count - 1)), y: size.height * (1 - min(1, max(0, sample.value / maxValue))))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            if samples.count > 1 {
                var area = path
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height)); area.closeSubpath()
                context.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.17), color.opacity(0.01)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                context.stroke(path, with: .color(color), lineWidth: 1.3)
            }
        }
    }
}
struct PopoverDashboard: View {
    @State private var confirmForceQuit = false
    @ObservedObject var monitor: Monitor
    let openWindow: () -> Void
    let openAbout: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void
    let openApp: (Int32) -> Void
    let openSummary: (Int32) -> Void
    @State private var tab: MetricTab = .memory
    @State private var overviewRanking: MetricTab = .cpu
    @State private var expandedApps = Set<ProcessIdentity>()
    @StateObject private var menuActions = AppActions()
    @State private var menuTarget: AppUsage?
    @State private var confirmMenuRestart = false
    @State private var confirmMenuQuit = false
    var samples: [Sample] { tab == .cpu ? monitor.history : monitor.metricHistory[tab.rawValue, default: []] }
    private func topApps(for metric: MetricTab) -> [AppUsage] {
        let apps = monitor.apps.filter { $0.bundleURL != nil || $0.icon != nil }
        return Array(sortedApps(apps, by: AppTableSort(column: metric == .memory ? .memory : .cpu, ascending: false)).prefix(5))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTabs(tabs: MetricTab.allCases, selection: $tab,
                title: { $0.title }, icon: { $0.icon }, color: { $0.color })
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
            HStack {
                Text(tab.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text("Systra").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
                Circle().fill(monitor.updated == nil ? .orange : .green).frame(width: 5, height: 5)
            }.padding(.horizontal, 4)
            SystraScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .overview: overview
                    case .memory: memory
                    case .cpu: cpu
                    case .disk: disk
                    case .network: network
                    case .gpu: gpu
                    case .temperature: temperatures
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }.background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack {
                Text(L("На этом Mac")).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                LiveUpdateLabel(monitor: monitor)
            }.padding(.horizontal, 4)
            HStack(spacing: 8) {
                Button(action: openWindow) { Label(L("Открыть Systra"), systemImage: "macwindow").frame(maxWidth: .infinity).frame(height: 31) }
                    .buttonStyle(.plain).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button(action: openSettings) { Image(systemName: "gearshape").frame(width: 31, height: 31) }.buttonStyle(.plain).help(L("Настройки")).accessibilityLabel(L("Настройки"))
                Button(action: openAbout) { Image(systemName: "info.circle").frame(width: 31, height: 31) }.buttonStyle(.plain).help(L("О Systra")).accessibilityLabel(L("О Systra"))
                Button(action: quit) { Image(systemName: "power").frame(width: 37, height: 31) }.buttonStyle(.plain)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous)).help(L("Выйти из Systra"))
            }.font(.system(size: 12, weight: .medium))
        }.padding(12).frame(width: 430, height: 650)
        .alert(L("Завершить принудительно?"), isPresented: $confirmForceQuit, presenting: menuTarget) { app in
                Button(L("Отмена"), role: .cancel) {}
                Button(L("Завершить принудительно"), role: .destructive) { menuActions.forceQuit(app) }
            } message: { app in Text(L("{0} будет завершено без сохранения. Несохранённые данные могут потеряться.", String(describing: app.name))) }
            .alert(L("Перезапустить приложение?"), isPresented: $confirmMenuRestart, presenting: menuTarget) { app in
            Button(L("Отмена"), role: .cancel) {}
            Button(L("Перезапустить"), role: .destructive) { menuActions.restart(app) }
        } message: { app in Text(L("Сохрани документы. {0} будет закрыто обычным запросом и открыто заново.", String(describing: app.name))) }
        .alert(L("Завершить приложение?"), isPresented: $confirmMenuQuit, presenting: menuTarget) { app in
            Button(L("Отмена"), role: .cancel) {}
            Button(L("Завершить"), role: .destructive) { menuActions.terminateApplication(app) }
        } message: { app in Text(L("Завершить {0}? Сохрани документы перед продолжением.", String(describing: app.name))) }
    }
    private func headline(_ value: String, subtitle: String, maximum: Double = 100) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(value).font(.system(size: 27, weight: .semibold)).monospacedDigit()
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            MiniChart(samples: samples, maximum: maximum, color: tab.color).frame(width: 115, height: 44)
                .help(L("История текущего сеанса, до 2 минут"))
        }
    }
    private func row(_ title: String, _ value: String, color: Color? = nil) -> some View {
        HStack(spacing: 8) {
            if let color { Circle().fill(color).frame(width: 7, height: 7) }
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }.font(.system(size: 12))
    }
    private var memory: some View {
        VStack(alignment: .leading, spacing: 8) {
            headline(bytes(monitor.usedMemory), subtitle: L("из {0} · {1} занято", String(describing: bytes(monitor.totalMemory)), String(describing: percent(Double(monitor.usedMemory) / Double(monitor.totalMemory) * 100))))
            HStack(spacing: 5) {
                Circle().fill(monitor.pressure == 4 ? .red : monitor.pressure == 2 ? .orange : .green).frame(width: 6, height: 6)
                Text(monitor.pressure == 4 ? L("Критичное давление памяти") : monitor.pressure == 2 ? L("Повышенное давление памяти") : monitor.pressure == 1 ? L("Нормальное давление памяти") : L("Давление памяти недоступно")).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(.blue).frame(width: geo.size.width * Double(monitor.appMemory) / Double(monitor.totalMemory))
                    Rectangle().fill(.orange).frame(width: geo.size.width * Double(monitor.wiredMemory) / Double(monitor.totalMemory))
                    Rectangle().fill(.mint).frame(width: geo.size.width * Double(monitor.compressedMemory) / Double(monitor.totalMemory))
                    Spacer(minLength: 0)
                }.background(.primary.opacity(0.09)).clipShape(Capsule())
            }.frame(height: 6).padding(.vertical, 6)
            row(L("Приложения"), bytes(monitor.appMemory), color: .blue)
            row(L("Wired · системная"), bytes(monitor.wiredMemory), color: .orange)
            row(L("Сжатая"), bytes(monitor.compressedMemory), color: .mint)
            row(L("Кэш"), bytes(monitor.cachedMemory), color: .gray)
            row("Swap", bytes(monitor.swap))
            Divider().padding(.vertical, 3)
            appList(for: tab)
        }
    }
    private var cpu: some View {
        VStack(alignment: .leading, spacing: 12) {
            headline(percent(monitor.cpu), subtitle: L("{0} логических ядер · весь Mac", String(describing: ProcessInfo.processInfo.activeProcessorCount)))
            ProgressView(value: monitor.cpu, total: 100).tint(.mint)
            Text(L("В списке приложений 100% соответствует одному ядру.")).font(.system(size: 12)).foregroundStyle(.secondary)
            Divider()
            appList(for: tab)
        }
    }
    private func appList(for metric: MetricTab) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Ресурсоёмкие приложения")).font(.system(size: 12)).foregroundStyle(.secondary)
            if topApps(for: metric).isEmpty { Text(L("Ожидание данных приложений…")).font(.caption).foregroundStyle(.secondary) }
            ForEach(topApps(for: metric)) { app in
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Button {
                            if !expandedApps.insert(app.identity).inserted { expandedApps.remove(app.identity) }
                        } label: {
                            Image(systemName: expandedApps.contains(app.identity) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).frame(width: 22, height: 52).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(L("{0} процессы {1}", String(describing: expandedApps.contains(app.identity) ? L("Свернуть") : L("Раскрыть")), String(describing: app.name)))
                        Button { openSummary(app.id) } label: {
                            HStack(spacing: 8) {
                                if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 26, height: 26) }
                                else { Image(systemName: "app").frame(width: 26, height: 26).foregroundStyle(.secondary) }
                                Text(app.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 6)
                                Text(metric == .memory ? bytes(app.memory) : percent(app.cpu)).font(.system(size: 14, weight: .semibold)).monospacedDigit().frame(width: 78, alignment: .trailing)
                            }.frame(height: 52).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(L("Сводка приложения {0}", String(describing: app.name)))
                    }
                    if expandedApps.contains(app.identity) {
                        HStack {
                            Text(L("Процессы · {0}", String(describing: app.count))).font(.system(size: 12)).foregroundStyle(.secondary)
                            Spacer()
                            Text("CPU").frame(width: 47, alignment: .trailing)
                            Text(L("Память")).frame(width: 65, alignment: .trailing)
                        }.font(.system(size: 12)).foregroundStyle(.tertiary).padding(.vertical, 5).padding(.leading, 12)
                        InlineProcessRows(app: app, byCPU: metric == .cpu, compact: true)
                        Button(L("Подробный инспектор…")) { openApp(app.id) }
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(metric.color)
                            .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }.contextMenu {
                    ApplicationContextMenu(app: app, restartEnabled: menuActions.restarting == nil, inspect: { openApp(app.id) }, restart: {
                        menuTarget = app; confirmMenuRestart = true
                    }, terminate: { menuTarget = app; confirmMenuQuit = true }, forceQuit: { menuTarget = app; confirmForceQuit = true })
                }
            }
            Text(L("Нажми строку для сводки, стрелку — для процессов. Память: сумма footprint процессов; возможен повторный учёт."))
                .font(.system(size: 12)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var disk: some View {
        VStack(alignment: .leading, spacing: 15) {
            headline(rate(monitor.diskRead), subtitle: L("Чтение · физические диски"), maximum: max(1, samples.map(\.value).max() ?? 1))
            row(L("Запись"), rate(monitor.diskWrite), color: .orange)
            Divider()
            if let free = monitor.hardware.diskFree, let total = monitor.hardware.diskTotal {
                row(L("Свободно"), bytes(free))
                row(L("Ёмкость"), bytes(total))
                ProgressView(value: Double(total - min(free, total)), total: Double(max(1, total))).tint(.orange)
                Text(L("Место на томе пользователя. I/O суммируется по доступным физическим дискам.")).font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            row(L("Прочитано за сеанс"), bytes(monitor.sessionRead))
            row(L("Записано за сеанс"), bytes(monitor.sessionWritten))
            Text(L("I/O отдельных процессов — в деталях приложения.")).font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var network: some View {
        VStack(alignment: .leading, spacing: 15) {
            headline(rate(monitor.download), subtitle: L("↓ Загрузка · Wi-Fi / Ethernet"), maximum: max(1, samples.map(\.value).max() ?? 1))
            row(L("↑ Отдача"), rate(monitor.upload), color: .cyan)
            Divider()
            row(L("Загружено за сеанс"), bytes(monitor.sessionReceived))
            row(L("Отправлено за сеанс"), bytes(monitor.sessionSent))
            Text(L("Физические интерфейсы: {0}", String(describing: (monitor.hardware.network?.keys.sorted().joined(separator: ", ")).flatMap { $0.isEmpty ? nil : $0 } ?? L("нет соединения")))).font(.caption2).foregroundStyle(.secondary)
            Text(L("VPN и локальный трафик отдельно не суммируются, чтобы избежать двойного учёта. Это скорость передачи, а не скорость тарифного плана."))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var gpu: some View {
        VStack(alignment: .leading, spacing: 15) {
            headline(percent(monitor.hardware.gpu), subtitle: monitor.hardware.gpuName)
            if let value = monitor.hardware.gpu { ProgressView(value: value, total: 100).tint(.purple) }
            row(L("Память драйвера"), monitor.hardware.gpuMemory.map(bytes) ?? "—", color: .purple)
            Text(L("Общая загрузка GPU из счётчиков драйвера. Это не выделенная VRAM; Apple Silicon использует общую память. Разбивка GPU по процессам пока недоступна."))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var temperatures: some View {
        VStack(alignment: .leading, spacing: 12) {
            headline(degrees(monitor.chipTemperature), subtitle: L("Максимум доступных датчиков кристалла"), maximum: 110)
            row(L("Батарея"), degrees(monitor.batteryTemperature), color: .pink)
            Divider()
            Text(L("Компоненты · {0} датчиков", String(describing: monitor.hardware.temperatures.count))).font(.caption).foregroundStyle(.secondary)
            TemperatureGroupsView(readings: monitor.hardware.temperatures, compact: true)
        }
    }
    private func overviewMetric(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
            .instrumentSurface(radius: 8)
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                overviewMetric(L("CPU · весь Mac"), value: percent(monitor.cpu), color: .mint)
                overviewMetric(L("Память"), value: bytes(monitor.usedMemory), color: .indigo)
                overviewMetric("GPU", value: percent(monitor.hardware.gpu), color: .purple)
                overviewMetric(L("Температура чипа"), value: degrees(monitor.chipTemperature), color: .pink)
                overviewMetric(L("Диск · ↓ чтение / ↑ запись"), value: "↓ \(rate(monitor.diskRead)) · ↑ \(rate(monitor.diskWrite))", color: .orange)
                overviewMetric(L("Сеть · ↓ загрузка / ↑ отдача"), value: "↓ \(rate(monitor.download)) · ↑ \(rate(monitor.upload))", color: .cyan)
            }
            Picker(L("Ресурсоёмкость"), selection: $overviewRanking) {
                Text(L("По CPU")).tag(MetricTab.cpu)
                Text(L("По памяти")).tag(MetricTab.memory)
            }.pickerStyle(.segmented)
            appList(for: overviewRanking)
        }
    }
}
