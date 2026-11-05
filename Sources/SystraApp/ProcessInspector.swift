import SwiftUI
import AppKit

struct InspectionTarget: Identifiable { let id: Int32 }
struct ProcessInspector: View {
    @ObservedObject var monitor: Monitor
    let target: Int32
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var sort = "memory"
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
        if sort == "tree" { return filtered.sorted { treeKey($0) < treeKey($1) } }
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
                    Text(app?.name ?? L("Приложение завершено")).font(.title2.weight(.medium))
                    Text(L("Процессов: {0} · PID {1}", String(describing: app?.count ?? 0), String(describing: target))).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(percent(app?.cpu)).font(.title2.monospacedDigit()).foregroundStyle(.mint)
                Text(app.map { bytes($0.memory) } ?? "—").font(.title2.monospacedDigit()).padding(.leading)
            }
            HStack {
                TextField(L("Имя, роль или PID"), text: $search).textFieldStyle(.roundedBorder).frame(width: 240)
                Spacer()
                Picker(L("Показать"), selection: $sort) { Text(L("По памяти")).tag("memory"); Text(L("По CPU")).tag("CPU"); Text(L("По RSS")).tag("RSS"); Text(L("По столбцу")).tag("column"); Text(L("Дерево процессов")).tag("tree") }.frame(width: 245)
            }
            Table(rows, selection: $selected, sortOrder: $sortOrder) {
                TableColumn(L("Процесс / роль"), value: \.name) { row in
                    HStack(spacing: 6) {
                        if sort == "tree" { Color.clear.frame(width: CGFloat(depth(row) * 12)); Image(systemName: "arrow.turn.down.right").foregroundStyle(.tertiary) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.pid == target ? L("Основной процесс") : row.role).font(.system(size: 14, weight: .medium)).lineLimit(1)
                            Text(row.name).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.padding(.vertical, 9)
                }.width(min: 235, ideal: 285)
                TableColumn("PID / PPID", value: \.pid) { row in
                    VStack(alignment: .leading, spacing: 3) { Text(String(row.pid)); Text("↳ \(row.parent)").foregroundStyle(.secondary).font(.system(size: 12)) }.monospacedDigit()
                }.width(85)
                TableColumn("CPU", value: \.cpuSortValue) { row in Text(row.cpu.map { percent($0) } ?? "—").monospacedDigit() }.width(70)
                TableColumn(L("Память"), value: \.memorySortValue) { row in Text(row.footprint.map(bytes) ?? "—").monospacedDigit() }.width(90)
                TableColumn(L("Память RSS"), value: \.rssSortValue) { row in Text(row.memory.map(bytes) ?? "—").monospacedDigit() }.width(95)
                TableColumn(L("Чтение/с"), value: \.readSortValue) { row in Text(rate(row.readRate)).monospacedDigit() }.width(95)
                TableColumn(L("Запись/с"), value: \.writeSortValue) { row in Text(rate(row.writeRate)).monospacedDigit() }.width(95)
            }.frame(minHeight: 270)
                .background(ProcessHeaderTooltips())
            if let process {
                VStack(alignment: .leading, spacing: 5) {
                    Text(process.executable).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).lineLimit(2)
                    if let total = process.diskTotal { Text(L("За время жизни процесса: прочитано {0}, записано {1}", String(describing: bytes(total.input)), String(describing: bytes(total.output)))).font(.caption2).foregroundStyle(.secondary) }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
            Text(L("CPU за интервал, 100% = одно ядро. Память — footprint, включая сжатые страницы; RSS — резидентные страницы. Общие страницы могут учитываться повторно. «—» означает, что macOS не предоставила данные или ещё нет второго замера. Дисковые счётчики процессов могут отличаться от физических операций SSD."))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if app?.name.localizedCaseInsensitiveContains("chrome") == true {
                Label(L("Renderer может обслуживать несколько вкладок или часть страницы. macOS не сообщает названия вкладок и их соответствие PID."), systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let message = actions.message { Text(message).font(.caption).foregroundStyle(.orange) }
            HStack {
                Text(L("Выбрано: {0}", String(describing: selected.count))).font(.caption).foregroundStyle(.secondary)
                Button(L("Завершить процессы…")) { confirmTerminate = true }.disabled(selectedProcesses.isEmpty || selectedProcesses.contains { $0.pid == ProcessInfo.processInfo.processIdentifier || $0.pid == 1 })
                Button(actions.restarting == nil ? L("Перезапустить приложение…") : L("Перезапуск…")) { confirmRestart = true }.disabled(app?.restartable != true || actions.restarting != nil)
                Button(L("Принудительно…"), role: .destructive) { confirmForceQuit = true }
                    .disabled(selectedProcesses.isEmpty || selectedProcesses.contains { $0.pid <= 1 || $0.pid == ProcessInfo.processInfo.processIdentifier })
                Spacer()
                Button(L("Готово")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 940, height: 650)
        .onChange(of: sort) { _, value in
            if value == "CPU" { sortOrder = [KeyPathComparator(\ProcessRow.cpuSortValue, order: .reverse), KeyPathComparator(\ProcessRow.pid)] }
            if value == "memory" { sortOrder = [KeyPathComparator(\ProcessRow.memorySortValue, order: .reverse), KeyPathComparator(\ProcessRow.pid)] }
            if value == "RSS" { sortOrder = [KeyPathComparator(\ProcessRow.rssSortValue, order: .reverse), KeyPathComparator(\ProcessRow.pid)] }
        }
        .onChange(of: sortOrder) { _, _ in if sort != "tree" { sort = "column" } }
        .alert(L("Завершить выбранные процессы принудительно?"), isPresented: $confirmForceQuit) {
            Button(L("Отмена"), role: .cancel) {}
            Button(L("Завершить принудительно"), role: .destructive) { for process in selectedProcesses { actions.forceQuit(process) } }
        } message: { Text(L("Процессы будут остановлены немедленно. Несохранённые данные и текущие задачи могут потеряться.")) }
        .alert(L("Завершить выбранные процессы?"), isPresented: $confirmTerminate) {
            Button(L("Отмена"), role: .cancel) {}
            Button(L("Завершить"), role: .destructive) { for process in selectedProcesses { actions.terminate(process) } }
        } message: { Text(L("Завершение renderer или агента может прервать вкладку или текущую задачу. Приложение может автоматически создать процесс заново.")) }
        .alert(L("Перезапустить всё приложение?"), isPresented: $confirmRestart) {
            Button(L("Отмена"), role: .cancel) {}
            Button(L("Перезапустить"), role: .destructive) { if let app { actions.restart(app) } }
        } message: { Text(L("Сохрани документы. Systra отправит обычный запрос на завершение, дождётся выхода и заново откроет приложение.")) }
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
                    if let scroll = table.enclosingScrollView { SystraScrollAppearance.apply(to: scroll) }
                    let descriptions = [
                        L("Процесс / роль"): L("Имя исполняемого файла и роль процесса внутри приложения: основной процесс, веб-контент, расширение, GPU или агент."),
                        "PID / PPID": L("PID — идентификатор процесса; PPID (строка со стрелкой) — идентификатор родительского процесса. После перезапуска PID обычно меняется."),
                        "CPU": AppColumn.cpu.help,
                        L("Память"): L("Память (footprint), учитываемая macOS за процессом, включая сжатые страницы. Общие страницы могут учитываться повторно. «—» — показатель недоступен."),
                        L("Память RSS"): AppColumn.rss.help,
                        L("Чтение/с"): AppColumn.read.help,
                        L("Запись/с"): AppColumn.write.help
                    ]
                    for column in table.tableColumns { column.headerToolTip = descriptions[column.title] }
                    return
                }
                ancestor = root.superview
            }
        }
    }
}
