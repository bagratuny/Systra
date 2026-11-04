import SwiftUI
import AppKit

struct InspectionTarget: Identifiable { let id: Int32 }
struct ProcessInspector: View {
    @ObservedObject var monitor: Monitor
    let target: Int32
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var sort = "Память"
    @State private var sortOrder = [KeyPathComparator(\ProcessRow.memorySortValue, order: .reverse), KeyPathComparator(\ProcessRow.pid)]
    @State private var selected = Set<ProcessIdentity>()
    @State private var confirmForceQuit = false
    @State private var confirmTerminate = false
    @State private var confirmRestart = false
    @StateObject private var actions = AppActions()
    var app: AppUsage? { monitor.apps.first { $0.id == target } }
    var rows: [ProcessRow] {
        let filtered = (app?.processes ?? []).filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.role.localizedCaseInsensitiveContains(search) || String($0.pid).contains(search)
        }
        if sort == "Дерево" { return filtered.sorted { treeKey($0) < treeKey($1) } }
        return filtered.sorted(using: sortOrder)
    }
    var process: ProcessRow? { selected.count == 1 ? app?.processes.first { selected.contains($0.id) } : nil }
    var selectedProcesses: [ProcessRow] { (app?.processes ?? []).filter { selected.contains($0.id) } }
    func treeKey(_ row: ProcessRow) -> String {
        let byPID = Dictionary(uniqueKeysWithValues: (app?.processes ?? []).map { ($0.pid, $0) })
        var path = [row.pid]
        var parent = row.parent
        var seen: Set<Int32> = [row.pid]
        while let ancestor = byPID[parent], seen.insert(parent).inserted {
            path.insert(parent, at: 0); parent = ancestor.parent
        }
        return path.map { String(format: "%010d", $0) }.joined(separator: "/")
    }
    func depth(_ row: ProcessRow) -> Int {
        let byPID = Dictionary(uniqueKeysWithValues: (app?.processes ?? []).map { ($0.pid, $0) })
        var result = 0, parent = row.parent
        var seen: Set<Int32> = [row.pid]
        while let ancestor = byPID[parent], seen.insert(parent).inserted { result += 1; parent = ancestor.parent }
        return min(5, result)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                if let icon = app?.icon { Image(nsImage: icon).resizable().frame(width: 36, height: 36) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(app?.name ?? "Приложение завершено").font(.title2.bold())
                    Text("Процессов: \(app?.count ?? 0) · PID \(target)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(percent(app?.cpu)).font(.title2.monospacedDigit()).foregroundStyle(.mint)
                Text(app.map { bytes($0.memory) } ?? "—").font(.title2.monospacedDigit()).padding(.leading)
            }
            HStack {
                TextField("Имя, роль или PID", text: $search).textFieldStyle(.roundedBorder).frame(width: 240)
                Spacer()
                Picker("Показать", selection: $sort) { Text("По памяти").tag("Память"); Text("По CPU").tag("CPU"); Text("По RSS").tag("RSS"); Text("По столбцу").tag("Столбец"); Text("Дерево процессов").tag("Дерево") }.frame(width: 245)
            }
            Table(rows, selection: $selected, sortOrder: $sortOrder) {
                TableColumn("Процесс / роль", value: \.name) { row in
                    HStack(spacing: 6) {
                        if sort == "Дерево" { Color.clear.frame(width: CGFloat(depth(row) * 12)); Image(systemName: "arrow.turn.down.right").foregroundStyle(.tertiary) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.pid == target ? "Основной процесс" : row.role).font(.system(size: 14, weight: .medium)).lineLimit(1)
                            Text(row.name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.padding(.vertical, 9)
                }.width(min: 235, ideal: 285)
                TableColumn("PID / PPID", value: \.pid) { row in
                    VStack(alignment: .leading, spacing: 3) { Text(String(row.pid)); Text("↳ \(row.parent)").foregroundStyle(.secondary).font(.system(size: 11)) }.monospacedDigit()
                }.width(85)
                TableColumn("CPU", value: \.cpuSortValue) { row in Text(row.cpu.map { String(format: "%.1f%%", $0) } ?? "—").monospacedDigit() }.width(70)
                TableColumn("Память", value: \.memorySortValue) { row in Text(row.footprint.map(bytes) ?? "—").monospacedDigit() }.width(90)
                TableColumn("Память RSS", value: \.rssSortValue) { row in Text(row.memory.map(bytes) ?? "—").monospacedDigit() }.width(95)
                TableColumn("Чтение/с", value: \.readSortValue) { row in Text(rate(row.readRate)).monospacedDigit() }.width(95)
                TableColumn("Запись/с", value: \.writeSortValue) { row in Text(rate(row.writeRate)).monospacedDigit() }.width(95)
            }.frame(minHeight: 270)
                .background(ProcessHeaderTooltips())
            if let process {
                VStack(alignment: .leading, spacing: 5) {
                    Text(process.executable).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).lineLimit(2)
                    if let total = process.diskTotal { Text("За время жизни процесса: прочитано \(bytes(total.input)), записано \(bytes(total.output))").font(.caption2).foregroundStyle(.secondary) }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
            Text("CPU за интервал, 100% = одно ядро. Память — footprint, включая сжатые страницы; RSS — резидентные страницы. Общие страницы могут учитываться повторно. «—» означает, что macOS не предоставила данные или ещё нет второго замера. Дисковые счётчики процессов могут отличаться от физических операций SSD.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if app?.name.localizedCaseInsensitiveContains("chrome") == true {
                Label("Renderer может обслуживать несколько вкладок или часть страницы. macOS не сообщает названия вкладок и их соответствие PID.", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let message = actions.message { Text(message).font(.caption).foregroundStyle(.orange) }
            HStack {
                Text("Выбрано: \(selected.count)").font(.caption).foregroundStyle(.secondary)
                Button("Завершить процессы…") { confirmTerminate = true }.disabled(selectedProcesses.isEmpty || selectedProcesses.contains { $0.pid == ProcessInfo.processInfo.processIdentifier || $0.pid == 1 })
                Button(actions.restarting == nil ? "Перезапустить приложение…" : "Перезапуск…") { confirmRestart = true }.disabled(app?.restartable != true || actions.restarting != nil)
                Button("Принудительно…", role: .destructive) { confirmForceQuit = true }
                    .disabled(selectedProcesses.isEmpty || selectedProcesses.contains { $0.pid <= 1 || $0.pid == ProcessInfo.processInfo.processIdentifier })
                Spacer()
                Button("Готово") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 940, height: 650)
        .onChange(of: sort) { _, value in
            if value == "CPU" { sortOrder = [KeyPathComparator(\ProcessRow.cpuSortValue, order: .reverse), KeyPathComparator(\ProcessRow.pid)] }
            if value == "Память" { sortOrder = [KeyPathComparator(\ProcessRow.memorySortValue, order: .reverse), KeyPathComparator(\ProcessRow.pid)] }
            if value == "RSS" { sortOrder = [KeyPathComparator(\ProcessRow.rssSortValue, order: .reverse), KeyPathComparator(\ProcessRow.pid)] }
        }
        .onChange(of: sortOrder) { _, _ in if sort != "Дерево" { sort = "Столбец" } }
        .alert("Завершить выбранные процессы принудительно?", isPresented: $confirmForceQuit) {
            Button("Отмена", role: .cancel) {}
            Button("Завершить принудительно", role: .destructive) { for process in selectedProcesses { actions.forceQuit(process) } }
        } message: { Text("Процессы будут остановлены немедленно. Несохранённые данные и текущие задачи могут потеряться.") }
        .alert("Завершить выбранные процессы?", isPresented: $confirmTerminate) {
            Button("Отмена", role: .cancel) {}
            Button("Завершить", role: .destructive) { for process in selectedProcesses { actions.terminate(process) } }
        } message: { Text("Завершение renderer или агента может прервать вкладку или текущую задачу. Приложение может автоматически создать процесс заново.") }
        .alert("Перезапустить всё приложение?", isPresented: $confirmRestart) {
            Button("Отмена", role: .cancel) {}
            Button("Перезапустить", role: .destructive) { if let app { actions.restart(app) } }
        } message: { Text("Сохрани документы. Systra отправит обычный запрос на завершение, дождётся выхода и заново откроет приложение.") }
    }
}

/// Native table headers expose their own tooltip property; cell help would only cover the body.
private struct ProcessHeaderTooltips: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            guard let view, view.window != nil else { return }
            func table(in root: NSView) -> NSTableView? {
                if let value = root as? NSTableView { return value }
                for child in root.subviews { if let value = table(in: child) { return value } }
                return nil
            }
            var ancestor = view.superview
            while let root = ancestor {
                if let table = table(in: root) {
                    let descriptions = [
                        "Процесс / роль": "Имя исполняемого файла и роль процесса внутри приложения: основной процесс, веб-контент, расширение, GPU или агент.",
                        "PID / PPID": "PID — идентификатор процесса; PPID (строка со стрелкой) — идентификатор родительского процесса. После перезапуска PID обычно меняется.",
                        "CPU": AppColumn.cpu.help,
                        "Память": "Память (footprint), учитываемая macOS за процессом, включая сжатые страницы. Общие страницы могут учитываться повторно. «—» — показатель недоступен.",
                        "Память RSS": AppColumn.rss.help,
                        "Чтение/с": AppColumn.read.help,
                        "Запись/с": AppColumn.write.help
                    ]
                    for column in table.tableColumns { column.headerToolTip = descriptions[column.title] }
                    return
                }
                ancestor = root.superview
            }
        }
    }
}
