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
            HStack(spacing: 10) {
                if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 34, height: 34) }
                else { Image(systemName: "gearshape").font(.title2).frame(width: 34, height: 34) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(live == nil ? "Завершено · последние показатели" : app.isBackground ? "Фоновое приложение · PID \(app.id)" : "Приложение · PID \(app.id)")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { copySummary() } label: { Image(systemName: "doc.on.doc").frame(width: 24, height: 26) }.buttonStyle(.borderless).help("Скопировать сводку")
                Button(action: close) { Image(systemName: "xmark.circle.fill").frame(width: 24, height: 26) }.buttonStyle(.borderless).help("Закрыть сводку").accessibilityLabel("Закрыть сводку приложения")
            }.padding(14)
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        summaryMetric("Память", symbol: "memorychip", value: bytes(app.memory), detail: String(format: "%.0f%% от %@ RAM", Double(app.memory) / Double(monitor.totalMemory) * 100, bytes(monitor.totalMemory)), color: .indigo)
                        summaryMetric("CPU", symbol: "cpu", value: String(format: "%.1f%%", app.cpu), detail: String(format: "%.2f ядра", app.cpu / 100), color: .mint)
                    }
                    HStack(spacing: 8) {
                        smallMetric("Чтение", value: rate(app.readBytesPerSecond), color: .orange)
                        smallMetric("Запись", value: rate(app.writeBytesPerSecond), color: .orange)
                        smallMetric("RSS", value: app.residentMemory.map(bytes) ?? "—", color: .purple)
                    }
                    roleBreakdown
                    AppHistoryChart(title: "Память", points: points, memory: true, color: .indigo)
                    AppHistoryChart(title: "CPU", points: points, memory: false, color: .mint)
                    details
                    Button("Подробный инспектор процессов…", action: inspect).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.indigo)
                    Text("Память — сумма footprint процессов; RSS — резидентные страницы. GPU и сетевой трафик по приложениям пока недоступны.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    if let message = actions.message { Text(message).font(.caption).foregroundStyle(.orange) }
                }.padding(14)
            }
            Divider().opacity(0.5)
            HStack(spacing: 8) {
                Button {
                    if let url = app.bundleURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                } label: { Image(systemName: "folder").frame(width: 24, height: 24) }.buttonStyle(.borderless).disabled(app.bundleURL == nil).help("Показать в Finder")
                Button("Перезапустить…") { confirmRestart = true }.disabled(live == nil || !app.restartable || actions.restarting != nil)
                Spacer(minLength: 0)
                Menu("Завершить") {
                    Button("Завершить…") { confirmQuit = true }
                    Button("Завершить принудительно…", role: .destructive) { confirmForceQuit = true }
                }.disabled(live == nil || app.id <= 1 || app.id == ProcessInfo.processInfo.processIdentifier)
            }.controlSize(.small).padding(12)
        }.background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.08)))
            .onAppear { updateDetails() }
            .onReceive(monitor.$apps) { apps in if let current = apps.first(where: { $0.identity == target.identity }) { lastApp = current } }
            .alert("Завершить принудительно?", isPresented: $confirmForceQuit) {
                Button("Отмена", role: .cancel) {}
                Button("Завершить принудительно", role: .destructive) { actions.forceQuit(app) }
            } message: { Text("\(app.name) будет завершено без сохранения. Несохранённые данные могут потеряться.") }
            .alert("Перезапустить приложение?", isPresented: $confirmRestart) {
                Button("Отмена", role: .cancel) {}
                Button("Перезапустить", role: .destructive) { actions.restart(app) }
            } message: { Text("Сохрани документы. \(app.name) будет завершено обычным запросом и открыто заново.") }
            .alert("Завершить приложение?", isPresented: $confirmQuit) {
                Button("Отмена", role: .cancel) {}
                Button("Завершить", role: .destructive) { actions.terminateApplication(app) }
            } message: { Text("Завершить \(app.name)? Сохрани документы перед продолжением.") }
    }
    private func summaryMetric(_ title: String, symbol: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.system(size: 10, weight: .medium)).foregroundStyle(color)
            Text(value).font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(color.opacity(0.075), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private func smallMetric(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(color)
            Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private var roleBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Внутри приложения").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Picker("Показатель", selection: $byCPU) { Text("Память").tag(false); Text("CPU").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 132)
            }
            if total > 0, let largest = groups.first {
                Text("\(largest.category.title): \(Int((byCPU ? largest.cpu : Double(largest.memory)) / total * 100))% \(byCPU ? "нагрузки" : "памяти")")
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
                        Text(group.category.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text("Процессов: \(group.count)").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(total > 0 ? String(format: "%.0f%%", (byCPU ? group.cpu : Double(group.memory)) / total * 100) : "—")
                        .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit().frame(width: 33, alignment: .trailing)
                    Text(byCPU ? String(format: "%.1f%%", group.cpu) : bytes(group.memory)).font(.system(size: 11, weight: .medium)).monospacedDigit().frame(width: 68, alignment: .trailing)
                }
            }
            Text("Веб-контент объединяет процессы страниц; процесс не соответствует одной именованной вкладке.").font(.system(size: 9)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Сведения").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            detailRow("PID", String(app.id))
            detailRow("Процессов", String(app.count))
            detailRow("Время работы", elapsedText(app.elapsedSeconds))
            detailRow("Версия", version)
            detailRow("Bundle ID", bundleID)
            VStack(alignment: .leading, spacing: 5) {
                Text("Путь").font(.system(size: 10)).foregroundStyle(.secondary)
                Text(app.bundleURL?.path ?? app.processes.first(where: { $0.pid == app.id })?.executable ?? "—")
                    .font(.system(size: 10, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).lineLimit(1).textSelection(.enabled) }.font(.system(size: 11))
    }
    private func updateDetails() {
        guard let url = target.bundleURL, let bundle = Bundle(url: url) else { return }
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        bundleID = bundle.bundleIdentifier ?? "—"
    }
    private func copySummary() {
        let text = "\(app.name) · PID \(app.id)\nCPU: \(String(format: "%.1f%%", app.cpu))\nПамять: \(bytes(app.memory))\nRSS: \(app.residentMemory.map(bytes) ?? "—")\nПроцессов: \(app.count)\nЧтение: \(rate(app.readBytesPerSecond))\nЗапись: \(rate(app.writeBytesPerSecond))"
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
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 12, weight: .semibold))
            if !values.isEmpty {
                Text(memory ? "Минимум \(bytes(UInt64(values.min() ?? 0))) · пик \(bytes(UInt64(values.max() ?? 0)))" : String(format: "Среднее %.1f%% · пик %.1f%%", values.reduce(0, +) / Double(values.count), values.max() ?? 0))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
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
                .overlay { if points.count < 2 { Text("Собираем историю…").font(.caption).foregroundStyle(.tertiary) } }
            HStack {
                if let first = points.first { Text(first.date.formatted(date: .omitted, time: .shortened)) }
                Spacer()
                if let last = points.last { Text(last.date.formatted(date: .omitted, time: .shortened)) }
            }.font(.system(size: 9)).foregroundStyle(.tertiary)
        }.padding(.vertical, 4)
    }
}
