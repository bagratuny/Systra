import SwiftUI
import AppKit

extension ProcessCategory {
    var color: Color {
        switch self { case .tabs: return .blue; case .extensions: return .mint; case .main: return .orange; case .gpu: return .purple; case .network: return .cyan; case .agents: return .pink; case .tools: return .indigo; case .other: return .gray }
    }
}
struct AppSummarySidebar: View {
    @ObservedObject var monitor: Monitor
    let target: AppUsage
    let close: () -> Void
    let inspect: () -> Void
    @State private var lastApp: AppUsage?
    @State private var byCPU = false
    @State private var confirmRestart = false
    @State private var confirmForceQuit = false
    @State private var confirmQuit = false
    @State private var version = "—"
    @State private var bundleID = "—"
    @StateObject private var actions = AppActions()
    private var live: AppUsage? { monitor.apps.first { $0.identity == target.identity } }
    private var app: AppUsage { live ?? lastApp ?? target }
    private var points: [AppTimelinePoint] { monitor.appHistory[target.identity, default: []] }
    private var groups: [AppRoleGroup] { appRoleGroups(app, byCPU: byCPU) }
    private var total: Double { groups.reduce(0) { $0 + (byCPU ? $1.cpu : Double($1.memory)) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 34, height: 36) }
                else { Image(systemName: "gearshape").font(.title2).frame(width: 34, height: 36) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(live == nil ? L("Завершено · последние показатели") : app.isBackground ? L("Фоновое приложение · PID {0}", String(describing: app.id)) : L("Приложение · PID {0}", String(describing: app.id)))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { copySummary() } label: { Image(systemName: "doc.on.doc").frame(width: 24, height: 26) }.buttonStyle(.borderless).help(L("Скопировать сводку"))
                Button(action: close) { Image(systemName: "xmark.circle.fill").frame(width: 24, height: 26) }.buttonStyle(.borderless).help(L("Закрыть сводку")).accessibilityLabel(L("Закрыть сводку приложения"))
            }.padding(16)
            Divider().opacity(0.5)
            SystraScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        summaryMetric(L("Память"), symbol: "memorychip", value: bytes(app.memory), detail: String(format: L("%.0f%% от %@ RAM"), Double(app.memory) / Double(monitor.totalMemory) * 100, bytes(monitor.totalMemory)), color: .indigo)
                        summaryMetric("CPU", symbol: "cpu", value: percent(app.cpu), detail: decimal(app.cpu / 100, digits: 2) + L(" ядра"), color: .mint)
                    }
                    HStack(spacing: 8) {
                        smallMetric(L("Чтение"), value: rate(app.readBytesPerSecond), color: .orange)
                        smallMetric(L("Запись"), value: rate(app.writeBytesPerSecond), color: .orange)
                        smallMetric("RSS", value: app.residentMemory.map(bytes) ?? "—", color: .purple)
                    }
                    roleBreakdown
                    AppHistoryChart(title: L("Память"), points: points, memory: true, color: .indigo)
                    AppHistoryChart(title: "CPU", points: points, memory: false, color: .mint)
                    details
                    Button(L("Подробный инспектор процессов…"), action: inspect).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.indigo)
                    Text(L("Память — сумма footprint процессов; RSS — резидентные страницы. GPU и сетевой трафик по приложениям пока недоступны."))
                        .font(.system(size: 12)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    if let message = actions.message { Text(message).font(.caption).foregroundStyle(.orange) }
                }.padding(16)
            }
            Divider().opacity(0.5)
            HStack(spacing: 8) {
                Button {
                    if let url = app.bundleURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                } label: { Image(systemName: "folder").frame(width: 24, height: 24) }.buttonStyle(.borderless).disabled(app.bundleURL == nil).help(L("Показать в Finder"))
                Button(L("Перезапустить…")) { confirmRestart = true }.disabled(live == nil || !app.restartable || actions.restarting != nil)
                Spacer(minLength: 0)
                Menu(L("Завершить")) {
                    Button(L("Завершить…")) { confirmQuit = true }
                    Button(L("Завершить принудительно…"), role: .destructive) { confirmForceQuit = true }
                }.disabled(live == nil || app.id <= 1 || app.id == ProcessInfo.processInfo.processIdentifier)
            }.controlSize(.small).padding(12)
        }.background(InstrumentStyle.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.08)))
            .onAppear { updateDetails() }
            .onReceive(monitor.$apps) { apps in if let current = apps.first(where: { $0.identity == target.identity }) { lastApp = current } }
            .alert(L("Завершить принудительно?"), isPresented: $confirmForceQuit) {
                Button(L("Отмена"), role: .cancel) {}
                Button(L("Завершить принудительно"), role: .destructive) { actions.forceQuit(app) }
            } message: { Text(L("{0} будет завершено без сохранения. Несохранённые данные могут потеряться.", String(describing: app.name))) }
            .alert(L("Перезапустить приложение?"), isPresented: $confirmRestart) {
                Button(L("Отмена"), role: .cancel) {}
                Button(L("Перезапустить"), role: .destructive) { actions.restart(app) }
            } message: { Text(L("Сохрани документы. {0} будет завершено обычным запросом и открыто заново.", String(describing: app.name))) }
            .alert(L("Завершить приложение?"), isPresented: $confirmQuit) {
                Button(L("Отмена"), role: .cancel) {}
                Button(L("Завершить"), role: .destructive) { actions.terminateApplication(app) }
            } message: { Text(L("Завершить {0}? Сохрани документы перед продолжением.", String(describing: app.name))) }
    }
    private func summaryMetric(_ title: String, symbol: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
            Text(value).font(.system(size: 23, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).instrumentSurface()
    }
    private func smallMetric(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(color)
            Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).instrumentSurface()
    }
    private var roleBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Внутри приложения")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Picker(L("Показатель"), selection: $byCPU) { Text(L("Память")).tag(false); Text("CPU").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 132)
            }
            if total > 0, let largest = groups.first {
                Text("\(largest.category.title): \(Int((byCPU ? largest.cpu : Double(largest.memory)) / total * 100))% \(byCPU ? L("нагрузки") : L("памяти"))")
                    .font(.system(size: 13, weight: .semibold)).lineLimit(2)
            }
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(groups) { group in
                        Rectangle().fill(group.category.color).frame(width: max(0, (geometry.size.width - CGFloat(max(0, groups.count - 1))) * (total > 0 ? (byCPU ? group.cpu : Double(group.memory)) / total : 0)))
                    }
                }.clipShape(Capsule())
            }.frame(height: 8)
            ForEach(groups) { group in
                HStack(spacing: 8) {
                    Image(systemName: group.category.symbol).font(.system(size: 12)).foregroundStyle(group.category.color).frame(width: 25, height: 28)
                        .background(group.category.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.category.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(L("Процессов: {0}", String(describing: group.count))).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(total > 0 ? String(format: "%.0f%%", (byCPU ? group.cpu : Double(group.memory)) / total * 100) : "—")
                        .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit().frame(width: 33, alignment: .trailing)
                    Text(byCPU ? percent(group.cpu) : bytes(group.memory)).font(.system(size: 12, weight: .medium)).monospacedDigit().frame(width: 68, alignment: .trailing)
                }
            }
            Text(L("Веб-контент объединяет процессы страниц; процесс не соответствует одной именованной вкладке.")).font(.system(size: 12)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }.padding(12).instrumentSurface()
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Сведения")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            detailRow("PID", String(app.id))
            detailRow(L("Процессов"), String(app.count))
            detailRow(L("Время работы"), elapsedText(app.elapsedSeconds))
            detailRow(L("Версия"), version)
            detailRow("Bundle ID", bundleID)
            VStack(alignment: .leading, spacing: 5) {
                Text(L("Путь")).font(.system(size: 12)).foregroundStyle(.secondary)
                Text(app.bundleURL?.path ?? app.processes.first(where: { $0.pid == app.id })?.executable ?? "—")
                    .font(.system(size: 10, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(12).instrumentSurface()
    }
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).lineLimit(1).textSelection(.enabled) }.font(.system(size: 12))
    }
    private func updateDetails() {
        guard let url = target.bundleURL, let bundle = Bundle(url: url) else { return }
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        bundleID = bundle.bundleIdentifier ?? "—"
    }
    private func copySummary() {
        let text = L("{0} · PID {1}\nCPU: {2}\nПамять: {3}\nRSS: {4}\nПроцессов: {5}\nЧтение: {6}\nЗапись: {7}", String(describing: app.name), String(describing: app.id), String(describing: percent(app.cpu)), String(describing: bytes(app.memory)), String(describing: app.residentMemory.map(bytes) ?? "—"), String(describing: app.count), String(describing: rate(app.readBytesPerSecond)), String(describing: rate(app.writeBytesPerSecond)))
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
}

struct AppHistoryChart: View {
    let title: String
    let points: [AppTimelinePoint]
    let memory: Bool
    let color: Color
    private var values: [Double] { points.map { memory ? Double($0.memory) : $0.cpu } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold))
            if !values.isEmpty {
                Text(memory ? L("Минимум {0} · пик {1}", String(describing: bytes(UInt64(values.min() ?? 0))), String(describing: bytes(UInt64(values.max() ?? 0)))) : String(format: L("Среднее %.1f%% · пик %.1f%%"), locale: AppLanguage.current.locale, values.reduce(0, +) / Double(values.count), values.max() ?? 0))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Canvas { context, size in
                guard values.count > 1 else { return }
                let low = memory ? (values.min() ?? 0) * 0.99 : 0
                let high = max(low + 1, (values.max() ?? 0) * 1.05)
                for level in [0.0, 0.5, 1.0] {
                    var grid = Path(); grid.move(to: CGPoint(x: 0, y: size.height * level)); grid.addLine(to: CGPoint(x: size.width, y: size.height * level))
                    context.stroke(grid, with: .color(.secondary.opacity(0.12)), style: StrokeStyle(lineWidth: 0.5, dash: [2,3]))
                }
                var line = Path()
                for (index, value) in values.enumerated() {
                    let point = CGPoint(x: size.width * Double(index) / Double(values.count - 1), y: size.height * (1 - min(1, max(0, (value - low) / (high - low)))))
                    if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
                }
                var fill = line; fill.addLine(to: CGPoint(x: size.width, y: size.height)); fill.addLine(to: CGPoint(x: 0, y: size.height)); fill.closeSubpath()
                context.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.28), color.opacity(0.01)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                context.stroke(line, with: .color(color), lineWidth: 1.5)
            }.frame(height: 90)
                .overlay { if points.count < 2 { Text(L("Собираем историю…")).font(.caption).foregroundStyle(.tertiary) } }
            HStack {
                if let first = points.first { Text(first.date.formatted(date: .omitted, time: .shortened)) }
                Spacer()
                if let last = points.last { Text(last.date.formatted(date: .omitted, time: .shortened)) }
            }.font(.system(size: 12)).foregroundStyle(.tertiary)
        }.padding(.vertical, 4)
    }
}
