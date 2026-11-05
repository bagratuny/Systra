import SwiftUI
import AppKit

enum MainTab: String, CaseIterable {
    case dashboard, apps, cpu, memory, disk, network, gpu, temperature
    var title: String {
        switch self { case .dashboard: return L("Дашборд"); case .apps: return L("Приложения"); case .cpu: return "CPU"; case .memory: return L("Память"); case .disk: return L("Диск"); case .network: return L("Сеть"); case .gpu: return "GPU"; case .temperature: return L("Температуры") }
    }
    var icon: String {
        switch self { case .dashboard: return "square.grid.2x2.fill"; case .apps: return "square.stack.3d.up.fill"; case .cpu: return "cpu"; case .memory: return "memorychip.fill"; case .disk: return "internaldrive.fill"; case .network: return "network"; case .gpu: return "square.3.layers.3d"; case .temperature: return "thermometer.medium" }
    }
    var color: Color {
        switch self { case .dashboard, .apps, .memory: return .indigo; case .cpu: return .mint; case .disk: return .orange; case .network: return .cyan; case .gpu: return .purple; case .temperature: return .pink }
    }
}

struct OverviewCard: View {
    let tab: MainTab
    var title: String? = nil
    var metricColor: Color? = nil
    let value: String
    let detail: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(title ?? tab.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(value).font(.system(size: 28, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2).frame(height: 32, alignment: .topLeading)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).frame(height: 136)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }.buttonStyle(InstrumentCardButtonStyle(tint: metricColor ?? tab.color)).help(L("Открыть {0}", String(describing: tab.title)))
    }
}
struct HistoryPanel: View {
    let title: String
    let samples: [Sample]
    let color: Color
    var maximum: Double = 100
    var rateScale = false
    var temperatureScale = false
    private var unit: MetricDisplayUnit { temperatureScale ? .temperature : rateScale ? .throughput : .percentage }
    private func axis(_ value: Double) -> String {
        temperatureScale ? decimal(value, digits: 0) + " °C" : rateScale ? rate(value) : "\(Int(value))%"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .medium))
                    Text(L("До 2 мин · замер каждые 2 с")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(samples.last.map { unit.formatted($0.value) } ?? "—")
                    .font(.system(size: 22, weight: .medium)).monospacedDigit().foregroundStyle(color)
            }
            HStack(spacing: 12) {
                ZStack {
                    VStack {
                        ForEach(0..<3) { index in
                            Rectangle().fill(.primary.opacity(0.06)).frame(height: 0.5)
                            if index < 2 { Spacer(minLength: 0) }
                        }
                    }
                    MiniChart(samples: samples, maximum: maximum, color: color)
                }.clipped()
                VStack(alignment: .trailing) {
                    Text(axis(maximum))
                    Spacer()
                    Text(axis(maximum / 2))
                    Spacer()
                    Text(axis(0))
                }.font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
            }.frame(minHeight: 85, maxHeight: .infinity)
            HStack { Text(L("Начало окна")); Spacer(); Text(L("Сейчас")) }
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(16).instrumentSurface()
    }
}

struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var navigation: WindowNavigation
    private var tab: MainTab {
        get { navigation.tab }
        nonmutating set { navigation.tab = newValue }
    }
    private var search: String { navigation.search }
    @State private var showSystemUptime = false
    @State private var sort = "CPU"
    @State private var selected: Int32?
    @State private var summaryTarget: AppUsage?
    @State private var visibility = "mine"
    @State private var confirm = false
    @State private var restartConfirm = false
    @State private var actionError: String?
    @State private var inspector: InspectionTarget?
    @StateObject private var actions = AppActions()
    var selectedApp: AppUsage? { monitor.apps.first { $0.id == selected } }
    var visibleApps: [AppUsage] { monitor.apps.filter { $0.icon != nil } }
    var rows: [AppUsage] {
        monitor.apps.filter { app in
            let included: Bool
            switch visibility {
            case "apps": included = app.bundleURL != nil
            case "background": included = app.isBackground && (app.bundleURL != nil || app.isUserOwned)
            case "all": included = true
            default: included = app.bundleURL != nil || app.isUserOwned
            }
            return included && (search.isEmpty || app.name.localizedCaseInsensitiveContains(search) || app.processes.contains { $0.name.localizedCaseInsensitiveContains(search) || String($0.pid).contains(search) })
        }
            .sorted {
                if sort == "CPU" { return $0.cpu == $1.cpu ? $0.id < $1.id : $0.cpu > $1.cpu }
                return $0.memory == $1.memory ? $0.id < $1.id : $0.memory > $1.memory
            }
    }
    var health: (String, Color) {
        if monitor.pressure == 4 { return (L("Критичное давление памяти"), .red) }
        if monitor.pressure == 2 { return (L("Повышенное давление памяти"), .orange) }
        if (monitor.chipTemperature ?? 0) > 90 { return (L("Высокая температура чипа"), .orange) }
        if monitor.cpu > 90 { return (L("Высокая нагрузка CPU"), .orange) }
        return (L("Мониторинг активен"), .mint)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                switch tab {
                case .dashboard: overview
                case .apps: applications
                case .cpu:
                    MetricHero(title: "CPU", value: percent(monitor.cpu), detail: L("{0} ядер · 100% = весь Mac", String(describing: ProcessInfo.processInfo.activeProcessorCount)), samples: monitor.history, color: .mint)
                        .frame(height: 165)
                    applications
                case .memory:
                    HStack(spacing: 12) {
                        MetricHero(title: L("Память"), value: bytes(monitor.usedMemory), detail: L("из {0} · swap {1}", String(describing: bytes(monitor.totalMemory)), String(describing: bytes(monitor.swap))), samples: history("memory"), color: .indigo)
                        memorySummary.frame(width: 260)
                    }.frame(height: 165)
                    applications
                case .disk: diskPane
                case .network: networkPane
                case .gpu: gpuPane
                case .temperature: temperaturePane
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let message = monitor.error ?? actionError ?? actions.message { Text(message).font(.caption).foregroundStyle(.orange) }
          }.frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
          if let target = summaryTarget {
            AppSummarySidebar(monitor: monitor, target: target, close: {
                selected = nil; summaryTarget = nil
            }, inspect: {
                if monitor.apps.contains(where: { $0.identity == target.identity }) { inspector = InspectionTarget(id: target.id) }
            }).id(target.identity).frame(width: 360)
                .padding(.vertical, tab == .temperature ? 16 : 0)
                .padding(.trailing, tab == .temperature ? 16 : 0)
          }
        }.padding(tab == .temperature ? 0 : 16).background(InstrumentStyle.canvas).frame(minWidth: summaryTarget == nil ? 880 : 960, minHeight: 580)
        .sheet(isPresented: $showSystemUptime) { UptimeDetailsView(monitor: monitor) }
        .onChange(of: selected) { _, value in
            if let value, let app = monitor.apps.first(where: { $0.id == value }) { summaryTarget = app }
            else if value == nil { summaryTarget = nil }
        }
        .onReceive(monitor.$summaryRequest) { value in
            if let value, let app = monitor.apps.first(where: { $0.id == value }) { selected = value; summaryTarget = app }
        }
        .onChange(of: tab) { _, value in
            if value == .memory { sort = "memory" }
            if value == .cpu { sort = "CPU" }
        }
        .onReceive(monitor.$inspectionRequest) { if let value = $0 { inspector = InspectionTarget(id: value) } }
        .sheet(item: $inspector) { ProcessInspector(monitor: monitor, target: $0.id) }
        .alert(L("Перезапустить приложение?"), isPresented: $restartConfirm) {
            Button(L("Отмена"), role: .cancel) {}
            Button(L("Перезапустить"), role: .destructive) { if let app = selectedApp { actions.restart(app) } }
        } message: { Text(L("Сохрани документы. Systra дождётся обычного завершения и снова откроет приложение. Если оно запросит сохранение, ответь в его окне.")) }
        .alert(L("Завершить приложение?"), isPresented: $confirm) {
            Button(L("Отмена"), role: .cancel) {}
            Button(L("Завершить"), role: .destructive) {
                guard let usage = selectedApp, usage.identity.isCurrent else { actionError = L("Процесс уже изменился. Обнови выбор."); return }
                if let app = NSRunningApplication(processIdentifier: usage.id) {
                    if !app.terminate() { actionError = L("Приложение отклонило запрос на завершение.") }
                } else if kill(usage.id, SIGTERM) != 0 { actionError = String(cString: strerror(errno)) }
            }
        } message: { Text(L("Будет отправлен обычный запрос на завершение. Сохрани документы перед продолжением.")) }
    }
    private func history(_ key: String) -> [Sample] { monitor.metricHistory[key, default: []] }
    private func rateMaximum(_ key: String) -> Double { max(1, history(key).map(\.value).max() ?? 1) }
    private var overview: some View {
        GeometryReader { geometry in
          SystraScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text(L("Состояние Mac")).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(L("{0} прилож. · {1} процессов", String(describing: visibleApps.count), String(describing: monitor.apps.reduce(0) { $0 + $1.count }))).font(.system(size: 12)).foregroundStyle(.secondary)
                    LiveUpdateLabel(monitor: monitor)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: geometry.size.width >= 800 ? 4 : 2), spacing: 12) {
                    OverviewCard(tab: .apps, value: "\(monitor.apps.filter { $0.bundleURL != nil }.count)", detail: L("Фоновые включены\n{0} процессов", String(describing: monitor.apps.reduce(0) { $0 + $1.count }))) { tab = .apps }
                    OverviewCard(tab: .cpu, value: percent(monitor.cpu), detail: L("{0} ядер\n100% = весь Mac", String(describing: ProcessInfo.processInfo.activeProcessorCount))) { tab = .cpu }
                    OverviewCard(tab: .memory, value: bytes(monitor.usedMemory), detail: L("из {0}\nSwap {1}", String(describing: bytes(monitor.totalMemory)), String(describing: bytes(monitor.swap)))) { tab = .memory }
                    OverviewCard(tab: .gpu, value: percent(monitor.hardware.gpu), detail: monitor.hardware.gpuName) { tab = .gpu }
                    OverviewCard(tab: .disk, value: rate(monitor.diskRead), detail: L("Чтение\nЗапись {0}", String(describing: rate(monitor.diskWrite)))) { tab = .disk }
                    OverviewCard(tab: .network, value: rate(monitor.download), detail: L("Загрузка\nОтдача {0}", String(describing: rate(monitor.upload)))) { tab = .network }
                    OverviewCard(tab: .temperature, value: degrees(monitor.chipTemperature), detail: L("Чип · максимум\nБатарея {0}", String(describing: degrees(monitor.batteryTemperature)))) { tab = .temperature }
                    SystemUptimeTile(snapshot: monitor.hardware.uptime) { showSystemUptime = true }
                }
                if geometry.size.width >= 1000 {
                    HStack(alignment: .top, spacing: 16) {
                        overviewHistory.frame(width: (geometry.size.width - 16) * 0.56)
                        overviewApplications.frame(maxWidth: .infinity)
                    }.frame(minHeight: 280, maxHeight: .infinity)
                } else {
                    overviewHistory.frame(height: 280)
                    overviewApplications.frame(height: 360)
                }
            }.frame(minHeight: geometry.size.height, alignment: .top)
          }
        }
    }
    private var overviewHistory: some View {
        HistoryPanel(title: L("Загрузка CPU"), samples: monitor.history, color: .mint)
            .frame(minHeight: 280, maxHeight: .infinity)
    }
    private var overviewApplications: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Ресурсоёмкие приложения")).font(.system(size: 14, weight: .medium))
                Spacer()
                Button(L("Все ›")) { tab = .apps }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            AppProcessList(apps: Array(sortedApps(visibleApps, by: AppTableSort(column: .cpu, ascending: false)).prefix(10)), byCPU: true, selected: $selected) { inspector = InspectionTarget(id: $0) }
        }.frame(minHeight: 280, maxHeight: .infinity)
    }
    private func applicationsSummaryCard(_ title: String, value: String, detail: String, color: Color, help: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 26, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2).frame(height: 32, alignment: .topLeading)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .instrumentSurface().help(help)
    }
    private func applicationLeader(_ app: AppUsage?, title: String, byCPU: Bool) -> some View {
        Button {
            if let app { selected = app.id; summaryTarget = app }
        } label: {
            HStack(spacing: 8) {
                if let icon = app?.icon { Image(nsImage: icon).resizable().frame(width: 24, height: 24) }
                else { Image(systemName: byCPU ? "cpu" : "memorychip").foregroundStyle(byCPU ? .mint : .indigo).frame(width: 24, height: 24) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(app?.name ?? L("Нет приложений")).font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let app { Text(byCPU ? percent(app.cpu) : bytes(app.memory)).font(.system(size: 12, weight: .semibold)).monospacedDigit() }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous)).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(app == nil).help(L("Открыть сводку лидера по {0} в текущем списке", String(describing: byCPU ? "CPU" : L("памяти"))))
    }
    private var applicationsOverview: some View {
        let summary = ApplicationsSummary(rows: rows)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Сводка по списку")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(search.isEmpty ? L("По текущему фильтру") : L("По поиску и фильтру")).font(.system(size: 12)).foregroundStyle(.secondary)
                LiveUpdateLabel(monitor: monitor)
            }
            HStack(spacing: 8) {
                applicationsSummaryCard(L("Процессы"), value: "\(summary.processCount)", detail: L("{0} прилож. · {1} служб", String(describing: summary.appCount), String(describing: summary.serviceCount)), color: .indigo, help: L("Количество процессов и групп в текущем списке. Приложения имеют app-пакет; остальные группы — службы и отдельные процессы."))
                applicationsSummaryCard(L("CPU · сумма"), value: percent(summary.cpu), detail: L("100% = одно ядро"), color: .mint, help: AppColumn.cpu.help)
                applicationsSummaryCard(L("Память · сумма"), value: bytes(summary.memory), detail: L("По текущему списку"), color: .indigo, help: AppColumn.memory.help + L(" Это сумма по списку, а не общий расход RAM Mac."))
                applicationsSummaryCard(L("Диск · сумма"), value: rate(summary.disk), detail: "↓ \(rate(summary.read)) · ↑ \(rate(summary.write))", color: .orange, help: L("Чтение и запись процессов в текущем списке. Суммируются только доступные счётчики. «—» — данных нет; это не физическая скорость SSD."))
            }
            HStack(spacing: 8) {
                applicationLeader(summary.cpuLeader, title: L("Больше всего CPU"), byCPU: true)
                applicationLeader(summary.memoryLeader, title: L("Больше всего памяти"), byCPU: false)
            }
        }
    }
    private var applications: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Приложения · {0}", String(describing: rows.count))).font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker(L("Показывать"), selection: $visibility) {
                    Text(L("Приложения и фоновые")).tag("mine")
                    Text(L("Только приложения")).tag("apps")
                    Text(L("Только фоновые")).tag("background")
                    Text(L("Все, включая системные")).tag("all")
                }.labelsHidden().frame(width: 205)
            }
            if tab == .apps { applicationsOverview.padding(.vertical, 4) }
            AppProcessList(apps: rows, byCPU: sort == "CPU", selected: $selected, detailed: tab == .apps) { inspector = InspectionTarget(id: $0) }.frame(minHeight: 140)
            HStack {
                Text(L("CPU: 100% = ядро · память: footprint")).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button(L("Инспектор…")) { if let selected { inspector = InspectionTarget(id: selected) } }.disabled(selectedApp == nil)
                Button(actions.restarting == nil ? L("Перезапустить…") : L("Перезапуск…")) { restartConfirm = true }.disabled(selectedApp?.restartable != true || actions.restarting != nil)
                Button(L("Завершить…")) { confirm = true }.disabled(selectedApp == nil || selected == ProcessInfo.processInfo.processIdentifier)
            }
        }
    }
    private var memorySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("По типам")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(.blue).frame(width: geo.size.width * Double(monitor.appMemory) / Double(monitor.totalMemory))
                    Rectangle().fill(.orange).frame(width: geo.size.width * Double(monitor.wiredMemory) / Double(monitor.totalMemory))
                    Rectangle().fill(.mint).frame(width: geo.size.width * Double(monitor.compressedMemory) / Double(monitor.totalMemory))
                    Spacer(minLength: 0)
                }.background(.primary.opacity(0.08)).clipShape(Capsule())
            }.frame(height: 5)
            stat(L("Приложения"), bytes(monitor.appMemory), .blue)
            stat("Wired", bytes(monitor.wiredMemory), .orange)
            stat(L("Сжатая"), bytes(monitor.compressedMemory), .mint)
            stat(L("Кэш"), bytes(monitor.cachedMemory), .gray)
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .instrumentSurface()
    }
    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack { Circle().fill(color).frame(width: 7, height: 7); Text(title).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit().fontWeight(.medium) }.font(.system(size: 12))
    }
    private var diskPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                TelemetryTile(title: L("Чтение"), symbol: "arrow.down", value: rate(monitor.diskRead), detail: L("Физические диски"), tint: .orange)
                TelemetryTile(title: L("Запись"), symbol: "arrow.up", value: rate(monitor.diskWrite), detail: L("Физические диски"), tint: .orange)
                TelemetryTile(title: L("Свободно"), symbol: "internaldrive", value: monitor.hardware.diskFree.map(bytes) ?? "—", detail: L("из {0} · том пользователя", String(describing: monitor.hardware.diskTotal.map(bytes) ?? "—")), tint: .orange)
            }
            HistoryPanel(title: L("Чтение + запись"), samples: history("disk"), color: .orange, maximum: rateMaximum("disk"), rateScale: true)
            HStack(spacing: 16) {
                TelemetryTile(title: L("Прочитано за сеанс"), symbol: "arrow.down", value: bytes(monitor.sessionRead), detail: L("С момента запуска Systra"), tint: .orange)
                TelemetryTile(title: L("Записано за сеанс"), symbol: "arrow.up", value: bytes(monitor.sessionWritten), detail: L("С момента запуска Systra"), tint: .orange)
            }
            Text(L("I/O отдельных процессов доступен в инспекторе приложения. Физические операции дисков и счётчики процессов могут отличаться из-за кэша.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var networkPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                TelemetryTile(title: L("Загрузка"), symbol: "arrow.down", value: rate(monitor.download), detail: "Wi-Fi / Ethernet", tint: .cyan)
                TelemetryTile(title: L("Отдача"), symbol: "arrow.up", value: rate(monitor.upload), detail: "Wi-Fi / Ethernet", tint: .cyan)
            }
            HistoryPanel(title: L("Загрузка + отдача"), samples: history("network"), color: .cyan, maximum: rateMaximum("network"), rateScale: true)
            HStack(spacing: 16) {
                TelemetryTile(title: L("Получено за сеанс"), symbol: "arrow.down", value: bytes(monitor.sessionReceived), detail: L("С момента запуска Systra"), tint: .cyan)
                TelemetryTile(title: L("Отправлено за сеанс"), symbol: "arrow.up", value: bytes(monitor.sessionSent), detail: L("С момента запуска Systra"), tint: .cyan)
            }
            Text(L("Физические интерфейсы: {0}. VPN и loopback отдельно не суммируются. Это текущий трафик, а не скорость тарифного плана.", String(describing: monitor.hardware.network?.keys.sorted().joined(separator: ", ") ?? L("недоступно")))).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var gpuPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                MetricCard(title: L("Загрузка GPU"), value: percent(monitor.hardware.gpu), detail: monitor.hardware.gpuName, progress: (monitor.hardware.gpu ?? 0) / 100, color: .purple)
                MetricCard(title: L("Память драйвера"), value: monitor.hardware.gpuMemory.map(bytes) ?? "—", detail: L("Системная память, используемая GPU"), progress: Double(monitor.hardware.gpuMemory ?? 0) / Double(monitor.totalMemory), color: .purple)
            }
            HistoryPanel(title: L("Загрузка GPU · %"), samples: history("gpu"), color: .purple)
            Text(L("Общая загрузка по счётчикам драйвера. На Apple Silicon память общая; это не выделенная VRAM. Разбивки GPU по приложениям пока нет.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var temperaturePane: some View {
        GeometryReader { viewport in
            SystraScrollView(unclipped: true) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        TelemetryTile(title: L("Чип"), symbol: "cpu", value: degrees(monitor.chipTemperature), detail: L("Максимум доступных датчиков кристалла"), tint: .pink)
                        TelemetryTile(title: L("Батарея"), symbol: "battery.75", value: degrees(monitor.batteryTemperature), detail: L("Максимум показаний датчиков батареи"), tint: .pink)
                    }
                    HistoryPanel(title: L("Температура чипа"), samples: history("temperature"), color: .pink, maximum: 110, temperatureScale: true).frame(height: 224)
                    HStack {
                        Text(L("Компоненты")).font(.headline)
                        Spacer()
                        Text(L("Датчиков: {0}", String(describing: monitor.hardware.temperatures.count))).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(L("Справа — самое высокое показание группы. Раскрой группу для отдельных датчиков; их названия macOS доступны при наведении."))
                        .font(.caption).foregroundStyle(.secondary)
                    TemperatureGroupsView(readings: monitor.hardware.temperatures)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .frame(width: viewport.size.width, alignment: .leading)
            }
        }
    }
}

struct MetricHero: View {
    let title: String
    let value: String
    let detail: String
    let samples: [Sample]
    let color: Color
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(value).font(.system(size: 34, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(L("Замер каждые 2 с")).font(.system(size: 12)).foregroundStyle(.secondary)
            }.frame(width: 165, alignment: .leading)
            VStack(spacing: 6) {
                ZStack {
                    VStack { ForEach(0..<3) { _ in Rectangle().fill(.secondary.opacity(0.1)).frame(height: 1); Spacer(minLength: 0) } }
                    MiniChart(samples: samples, maximum: 100, color: color)
                }
                HStack { Text(L("Последние 2 минуты")); Spacer(); Text("0–100%") }.font(.system(size: 12)).foregroundStyle(.tertiary)
            }
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
            .instrumentSurface()
    }
}
