import SwiftUI
import AppKit

enum MainTab: String, CaseIterable {
    case dashboard, apps, cpu, memory, disk, network, gpu, temperature
    var title: String {
        switch self { case .dashboard: return "Дашборд"; case .apps: return "Приложения"; case .cpu: return "CPU"; case .memory: return "Память"; case .disk: return "Диск"; case .network: return "Сеть"; case .gpu: return "GPU"; case .temperature: return "Температуры" }
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
    let value: String
    let detail: String
    var samples: [Sample] = []
    var maximum: Double = 100
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(tab.title, systemImage: tab.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(tab.color)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                }
                HStack(alignment: .center) {
                    Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 8)
                    if tab == .apps {
                        Image(systemName: tab.icon).font(.system(size: 28)).foregroundStyle(tab.color.opacity(0.65)).frame(width: 92, height: 37)
                    } else {
                        MiniChart(samples: samples, maximum: maximum, color: tab.color).frame(width: 92, height: 37)
                    }
                }
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).frame(height: 29, alignment: .topLeading)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(tab.color.opacity(0.065), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tab.color.opacity(0.12)))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }.buttonStyle(.plain).help("Открыть \(tab.title)")
    }
}
struct HistoryPanel: View {
    let title: String
    let samples: [Sample]
    let color: Color
    var maximum: Double = 100
    var rateScale = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Последние 2 минуты").font(.caption2).foregroundStyle(.secondary)
            }
            ZStack {
                VStack { ForEach(0..<3) { _ in Rectangle().fill(.secondary.opacity(0.12)).frame(height: 1); Spacer(minLength: 0) } }
                MiniChart(samples: samples, maximum: maximum, color: color)
            }.frame(minHeight: 85, maxHeight: .infinity)
            HStack {
                Text("0")
                Spacer()
                Text(rateScale ? rate(maximum) : String(format: "%.0f", maximum))
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    @State private var visibility = "Мои процессы"
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
            case "Приложения": included = app.bundleURL != nil
            case "Фоновые": included = app.isBackground && (app.bundleURL != nil || app.isUserOwned)
            case "Все процессы": included = true
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
        if monitor.pressure == 4 { return ("Критичное давление памяти", .red) }
        if monitor.pressure == 2 { return ("Повышенное давление памяти", .orange) }
        if (monitor.chipTemperature ?? 0) > 90 { return ("Высокая температура чипа", .orange) }
        if monitor.cpu > 90 { return ("Высокая нагрузка CPU", .orange) }
        return ("Мониторинг активен", .mint)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                switch tab {
                case .dashboard: overview
                case .apps: applications
                case .cpu:
                    MetricHero(title: "CPU", value: String(format: "%.1f%%", monitor.cpu), detail: "\(ProcessInfo.processInfo.activeProcessorCount) ядер · 100% = весь Mac", samples: monitor.history, color: .mint)
                        .frame(height: 165)
                    applications
                case .memory:
                    HStack(spacing: 10) {
                        MetricHero(title: "Память", value: bytes(monitor.usedMemory), detail: "из \(bytes(monitor.totalMemory)) · swap \(bytes(monitor.swap))", samples: history("memory"), color: .indigo)
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
          }
        }.padding(12).frame(minWidth: summaryTarget == nil ? 880 : 960, minHeight: 580)
        .sheet(isPresented: $showSystemUptime) { UptimeDetailsView(monitor: monitor) }
        .onChange(of: selected) { _, value in
            if let value, let app = monitor.apps.first(where: { $0.id == value }) { summaryTarget = app }
            else if value == nil { summaryTarget = nil }
        }
        .onReceive(monitor.$summaryRequest) { value in
            if let value, let app = monitor.apps.first(where: { $0.id == value }) { selected = value; summaryTarget = app }
        }
        .onChange(of: tab) { _, value in
            if value == .memory { sort = "Память" }
            if value == .cpu { sort = "CPU" }
        }
        .onReceive(monitor.$inspectionRequest) { if let value = $0 { inspector = InspectionTarget(id: value) } }
        .sheet(item: $inspector) { ProcessInspector(monitor: monitor, target: $0.id) }
        .alert("Перезапустить приложение?", isPresented: $restartConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Перезапустить", role: .destructive) { if let app = selectedApp { actions.restart(app) } }
        } message: { Text("Сохрани документы. Systra дождётся обычного завершения и снова откроет приложение. Если оно запросит сохранение, ответь в его окне.") }
        .alert("Завершить приложение?", isPresented: $confirm) {
            Button("Отмена", role: .cancel) {}
            Button("Завершить", role: .destructive) {
                guard let usage = selectedApp, usage.identity.isCurrent else { actionError = "Процесс уже изменился. Обнови выбор."; return }
                if let app = NSRunningApplication(processIdentifier: usage.id) {
                    if !app.terminate() { actionError = "Приложение отклонило запрос на завершение." }
                } else if kill(usage.id, SIGTERM) != 0 { actionError = String(cString: strerror(errno)) }
            }
        } message: { Text("Будет отправлен обычный запрос на завершение. Сохрани документы перед продолжением.") }
    }
    private func history(_ key: String) -> [Sample] { monitor.metricHistory[key, default: []] }
    private func rateMaximum(_ key: String) -> Double { max(1, history(key).map(\.value).max() ?? 1) }
    private var overview: some View {
        GeometryReader { geometry in
          ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Состояние Mac").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("Приложений: \(visibleApps.count) · процессов: \(monitor.apps.reduce(0) { $0 + $1.count })").font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                    OverviewCard(tab: .apps, value: "\(monitor.apps.filter { $0.bundleURL != nil }.count)", detail: "Приложений · всего процессов: \(monitor.apps.reduce(0) { $0 + $1.count })\nВключая фоновые службы") { tab = .apps }
                    OverviewCard(tab: .cpu, value: String(format: "%.1f%%", monitor.cpu), detail: "\(ProcessInfo.processInfo.activeProcessorCount) логических ядер · весь Mac", samples: monitor.history) { tab = .cpu }
                    OverviewCard(tab: .memory, value: bytes(monitor.usedMemory), detail: "из \(bytes(monitor.totalMemory)) · swap \(bytes(monitor.swap))", samples: history("memory")) { tab = .memory }
                    OverviewCard(tab: .gpu, value: percent(monitor.hardware.gpu), detail: monitor.hardware.gpuName, samples: history("gpu")) { tab = .gpu }
                    OverviewCard(tab: .disk, value: rate(monitor.diskRead), detail: "Чтение · запись \(rate(monitor.diskWrite))", samples: history("disk"), maximum: rateMaximum("disk")) { tab = .disk }
                    OverviewCard(tab: .network, value: rate(monitor.download), detail: "Загрузка · отдача \(rate(monitor.upload))", samples: history("network"), maximum: rateMaximum("network")) { tab = .network }
                    OverviewCard(tab: .temperature, value: degrees(monitor.chipTemperature), detail: "Максимум датчиков чипа · батарея \(degrees(monitor.batteryTemperature))", samples: history("temperature"), maximum: 110) { tab = .temperature }
                    SystemUptimeTile(snapshot: monitor.hardware.uptime) { showSystemUptime = true }
                }
                HStack(alignment: .top, spacing: 10) {
                    HistoryPanel(title: "CPU · последние 2 минуты", samples: monitor.history, color: .mint).frame(maxWidth: .infinity).frame(minHeight: 235, maxHeight: .infinity)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Ресурсоёмкие приложения").font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Button("Все ›") { tab = .apps }.buttonStyle(.plain).foregroundStyle(.indigo)
                        }
                        AppProcessList(apps: Array(visibleApps.sorted { $0.cpu > $1.cpu }.prefix(10)), byCPU: true, selected: $selected) { inspector = InspectionTarget(id: $0) }
                    }.frame(maxWidth: .infinity).frame(minHeight: 235, maxHeight: .infinity)
                }.frame(minHeight: 235, maxHeight: .infinity)
            }.frame(minHeight: max(0, geometry.size.height - 3), alignment: .top).padding(.bottom, 3)
          }
        }
    }
    private func applicationsSummaryCard(_ title: String, value: String, detail: String, color: Color, help: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            Text(value).font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2).frame(height: 26, alignment: .topLeading)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(color.opacity(0.065), in: RoundedRectangle(cornerRadius: 12, style: .continuous)).help(help)
    }
    private func applicationLeader(_ app: AppUsage?, title: String, byCPU: Bool) -> some View {
        Button {
            if let app { selected = app.id; summaryTarget = app }
        } label: {
            HStack(spacing: 8) {
                if let icon = app?.icon { Image(nsImage: icon).resizable().frame(width: 24, height: 24) }
                else { Image(systemName: byCPU ? "cpu" : "memorychip").foregroundStyle(byCPU ? .mint : .indigo).frame(width: 24, height: 24) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(app?.name ?? "Нет приложений").font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let app { Text(byCPU ? String(format: "%.1f%%", app.cpu) : bytes(app.memory)).font(.system(size: 12, weight: .semibold)).monospacedDigit() }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous)).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(app == nil).help("Открыть сводку лидера по \(byCPU ? "CPU" : "памяти") в текущем списке")
    }
    private var applicationsOverview: some View {
        let summary = ApplicationsSummary(rows: rows)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Сводка по списку").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(search.isEmpty ? "С учётом фильтра" : "С учётом поиска и фильтра").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                applicationsSummaryCard("Процессы", value: "\(summary.processCount)", detail: "\(summary.appCount) прилож. · \(summary.serviceCount) служб", color: .indigo, help: "Количество процессов и групп в текущем списке. Приложения имеют app-пакет; остальные группы — службы и отдельные процессы.")
                applicationsSummaryCard("CPU · сумма", value: String(format: "%.1f%%", summary.cpu), detail: "100% = одно ядро", color: .mint, help: AppColumn.cpu.help)
                applicationsSummaryCard("Память · сумма", value: bytes(summary.memory), detail: "Footprint процессов", color: .indigo, help: AppColumn.memory.help + " Это сумма по списку, а не общий расход RAM Mac.")
                applicationsSummaryCard("Диск · сумма", value: rate(summary.disk), detail: "↓ \(rate(summary.read)) · ↑ \(rate(summary.write))", color: .orange, help: "Чтение и запись процессов в текущем списке. Суммируются только доступные счётчики. «—» — данных нет; это не физическая скорость SSD.")
            }
            HStack(spacing: 8) {
                applicationLeader(summary.cpuLeader, title: "Больше всего CPU", byCPU: true)
                applicationLeader(summary.memoryLeader, title: "Больше всего памяти", byCPU: false)
            }
        }
    }
    private var applications: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Приложения · \(rows.count)").font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker("Показывать", selection: $visibility) {
                    Text("Приложения и фоновые").tag("Мои процессы")
                    Text("Только приложения").tag("Приложения")
                    Text("Только фоновые").tag("Фоновые")
                    Text("Все, включая системные").tag("Все процессы")
                }.labelsHidden().frame(width: 205)
            }
            if tab == .apps { applicationsOverview.padding(.vertical, 4) }
            AppProcessList(apps: rows, byCPU: sort == "CPU", selected: $selected, detailed: tab == .apps) { inspector = InspectionTarget(id: $0) }.frame(minHeight: 140)
            HStack {
                Text("CPU: 100% = ядро · память: footprint").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Инспектор…") { if let selected { inspector = InspectionTarget(id: selected) } }.disabled(selectedApp == nil)
                Button(actions.restarting == nil ? "Перезапустить…" : "Перезапуск…") { restartConfirm = true }.disabled(selectedApp?.restartable != true || actions.restarting != nil)
                Button("Завершить…") { confirm = true }.disabled(selectedApp == nil || selected == ProcessInfo.processInfo.processIdentifier)
            }
        }
    }
    private var memorySummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("По типам").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(.blue).frame(width: geo.size.width * Double(monitor.appMemory) / Double(monitor.totalMemory))
                    Rectangle().fill(.orange).frame(width: geo.size.width * Double(monitor.wiredMemory) / Double(monitor.totalMemory))
                    Rectangle().fill(.mint).frame(width: geo.size.width * Double(monitor.compressedMemory) / Double(monitor.totalMemory))
                    Spacer(minLength: 0)
                }.background(.primary.opacity(0.08)).clipShape(Capsule())
            }.frame(height: 5)
            stat("Приложения", bytes(monitor.appMemory), .blue)
            stat("Wired", bytes(monitor.wiredMemory), .orange)
            stat("Сжатая", bytes(monitor.compressedMemory), .mint)
            stat("Кэш", bytes(monitor.cachedMemory), .gray)
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack { Circle().fill(color).frame(width: 7, height: 7); Text(title).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit().fontWeight(.medium) }.font(.system(size: 11))
    }
    private var diskPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                TelemetryTile(title: "ЧТЕНИЕ", symbol: "arrow.down", value: rate(monitor.diskRead), detail: "Физические диски", tint: .orange)
                TelemetryTile(title: "ЗАПИСЬ", symbol: "arrow.up", value: rate(monitor.diskWrite), detail: "Физические диски", tint: .orange)
                TelemetryTile(title: "СВОБОДНО", symbol: "internaldrive", value: monitor.hardware.diskFree.map(bytes) ?? "—", detail: "из \(monitor.hardware.diskTotal.map(bytes) ?? "—") · том пользователя", tint: .orange)
            }
            HistoryPanel(title: "Чтение + запись", samples: history("disk"), color: .orange, maximum: rateMaximum("disk"), rateScale: true)
            HStack(spacing: 14) {
                TelemetryTile(title: "ПРОЧИТАНО ЗА СЕАНС", symbol: "arrow.down", value: bytes(monitor.sessionRead), detail: "С момента запуска Systra", tint: .orange)
                TelemetryTile(title: "ЗАПИСАНО ЗА СЕАНС", symbol: "arrow.up", value: bytes(monitor.sessionWritten), detail: "С момента запуска Systra", tint: .orange)
            }
            Text("I/O отдельных процессов доступен в инспекторе приложения. Физические операции дисков и счётчики процессов могут отличаться из-за кэша.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var networkPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                TelemetryTile(title: "ЗАГРУЗКА", symbol: "arrow.down", value: rate(monitor.download), detail: "Wi-Fi / Ethernet", tint: .cyan)
                TelemetryTile(title: "ОТДАЧА", symbol: "arrow.up", value: rate(monitor.upload), detail: "Wi-Fi / Ethernet", tint: .cyan)
            }
            HistoryPanel(title: "Загрузка + отдача", samples: history("network"), color: .cyan, maximum: rateMaximum("network"), rateScale: true)
            HStack(spacing: 14) {
                TelemetryTile(title: "ПОЛУЧЕНО ЗА СЕАНС", symbol: "arrow.down", value: bytes(monitor.sessionReceived), detail: "С момента запуска Systra", tint: .cyan)
                TelemetryTile(title: "ОТПРАВЛЕНО ЗА СЕАНС", symbol: "arrow.up", value: bytes(monitor.sessionSent), detail: "С момента запуска Systra", tint: .cyan)
            }
            Text("Физические интерфейсы: \(monitor.hardware.network?.keys.sorted().joined(separator: ", ") ?? "недоступно"). VPN и loopback отдельно не суммируются. Это текущий трафик, а не скорость тарифного плана.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var gpuPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                MetricCard(title: "ЗАГРУЗКА GPU", value: percent(monitor.hardware.gpu), detail: monitor.hardware.gpuName, progress: (monitor.hardware.gpu ?? 0) / 100, color: .purple)
                MetricCard(title: "ПАМЯТЬ ДРАЙВЕРА", value: monitor.hardware.gpuMemory.map(bytes) ?? "—", detail: "Системная память, используемая GPU", progress: Double(monitor.hardware.gpuMemory ?? 0) / Double(monitor.totalMemory), color: .purple)
            }
            HistoryPanel(title: "Загрузка GPU · %", samples: history("gpu"), color: .purple)
            Text("Общая загрузка по счётчикам драйвера. На Apple Silicon память общая; это не выделенная VRAM. Разбивки GPU по приложениям пока нет.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var temperaturePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                TelemetryTile(title: "ЧИП", symbol: "cpu", value: degrees(monitor.chipTemperature), detail: "Максимум доступных датчиков кристалла", tint: .pink)
                TelemetryTile(title: "БАТАРЕЯ", symbol: "battery.75", value: degrees(monitor.batteryTemperature), detail: "Максимум показаний датчиков батареи", tint: .pink)
            }
            HistoryPanel(title: "Температура чипа · °C", samples: history("temperature"), color: .pink, maximum: 110).frame(height: 160)
            HStack {
                Text("Компоненты").font(.headline)
                Spacer()
                Text("Датчиков: \(monitor.hardware.temperatures.count)").font(.caption).foregroundStyle(.secondary)
            }
            Text("Справа — самое высокое показание группы. Раскрой группу для отдельных датчиков; их названия macOS доступны при наведении.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView { TemperatureGroupsView(readings: monitor.hardware.temperatures) }
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
                Text(value).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("Обновление · 2 с").font(.system(size: 9)).foregroundStyle(.tertiary)
            }.frame(width: 165, alignment: .leading)
            VStack(spacing: 6) {
                ZStack {
                    VStack { ForEach(0..<3) { _ in Rectangle().fill(.secondary.opacity(0.1)).frame(height: 1); Spacer(minLength: 0) } }
                    MiniChart(samples: samples, maximum: 100, color: color)
                }
                HStack { Text("Последние 2 минуты"); Spacer(); Text("0–100%") }.font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
