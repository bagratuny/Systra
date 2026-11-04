import SwiftUI
import AppKit

/// Application groups and their root processes remain distinct selectable rows.
enum MonitorRowID: Hashable {
    case app(ProcessIdentity)
    case process(ProcessIdentity)
}

func orderedProcesses(_ processes: [ProcessRow], byCPU: Bool) -> [ProcessRow] {
    processes.sorted {
        if byCPU {
            if $0.cpu != $1.cpu { return ($0.cpu ?? -1) > ($1.cpu ?? -1) }
        } else {
            let lhs = $0.footprint ?? $0.memory ?? 0
            let rhs = $1.footprint ?? $1.memory ?? 0
            if lhs != rhs { return lhs > rhs }
        }
        return $0.pid < $1.pid
    }
}

struct InlineProcessRows: View {
    let app: AppUsage
    let byCPU: Bool
    var compact = false
    var selectedProcesses: Set<ProcessIdentity> = []
    var selectProcess: ((ProcessIdentity) -> Void)? = nil
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(orderedProcesses(app.processes, byCPU: byCPU)) { process in
                HStack(spacing: compact ? 7 : 10) {
                    Image(systemName: process.pid == app.id ? "app" : "arrow.turn.down.right")
                        .font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 14)
                    VStack(alignment: .leading, spacing: compact ? 3 : 1) {
                        Text(process.pid == app.id ? "Основной процесс" : (process.role == "Процесс" ? process.name : process.role))
                            .font(.system(size: compact ? 11 : 14, weight: .medium)).lineLimit(1)
                        Text(compact ? "PID \(process.pid)" : "\(process.name) · PID \(process.pid)")
                            .font(.system(size: compact ? 10 : 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 3)
                    Text(process.cpu.map { String(format: "%.1f%%", $0) } ?? "—")
                        .font(.system(size: compact ? 11 : 14)).monospacedDigit()
                        .foregroundStyle(.secondary).frame(width: compact ? 47 : 80, alignment: .trailing)
                    Text((process.footprint ?? process.memory).map(bytes) ?? "—")
                        .font(.system(size: compact ? 11 : 14, weight: .medium)).monospacedDigit()
                        .frame(width: compact ? 65 : 110, alignment: .trailing)
                }.padding(.vertical, compact ? 8 : 9).padding(.horizontal, compact ? 5 : 12)
                    .frame(maxWidth: .infinity).contentShape(Rectangle())
                    .background(selectedProcesses.contains(process.id) ? Color.accentColor.opacity(0.18) : .clear)
                    .onTapGesture { selectProcess?(process.id) }
                    .help("\(process.executable)\nCPU за интервал · память footprint")
                Divider().opacity(0.35)
            }
        }.padding(.leading, compact ? 7 : 25)
    }
}

struct AppProcessList: View {
    let apps: [AppUsage]
    let byCPU: Bool
    @Binding var selected: Int32?
    var detailed = false
    let inspect: (Int32) -> Void
    @State private var confirmSelectionForceQuit = false
    @State private var forceApps: [AppUsage] = []
    @State private var forceProcesses: [ProcessRow] = []
    @State private var confirmForceQuit = false
    @State private var selection = RowSelection<MonitorRowID>()
    @State private var expanded = Set<ProcessIdentity>()
    @State private var overrideSort: AppTableSort?
    @State private var visibleColumns: Set<AppColumn> = [.pid, .cpu, .memory, .rss, .processes, .read, .write, .uptime]
    @State private var menuTarget: AppUsage?
    @State private var confirmRestart = false
    @State private var confirmQuit = false
    @State private var menuError: String?
    @StateObject private var actions = AppActions()
    private var sorting: AppTableSort { overrideSort ?? AppTableSort(column: byCPU ? .cpu : .memory, ascending: false) }
    private var columns: [AppColumn] { detailed ? [.name] + AppColumn.allCases.filter { $0 != .name && visibleColumns.contains($0) } : [.name, .cpu, .memory] }
    private var orderedApps: [AppUsage] { sortedApps(apps, by: sorting) }
    private var minimumWidth: CGFloat { columns.reduce(0) { $0 + $1.width } + CGFloat(columns.count - 1) * 10 + 52 }
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    VStack(spacing: 8) {
                        header
                            .zIndex(1)
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(orderedApps) { app in
                                    VStack(spacing: 0) {
                                        appRow(app)
                                        if expanded.contains(app.identity) {
                                            if detailed { detailedProcesses(app) }
                                            else { InlineProcessRows(app: app, byCPU: sorting.column == .cpu, selectedProcesses: Set(selection.items.compactMap { if case .process(let id) = $0 { return id }; return nil }), selectProcess: { selectRow(.process($0)) }).padding(.trailing, 25).background(.primary.opacity(0.02)) }
                                        }
                                        Divider().opacity(0.3)
                                    }
                                }
                                if apps.isEmpty { Text("Ничего не найдено").foregroundStyle(.secondary).padding(24) }
                            }
                        }
                    }.frame(width: max(geometry.size.width - 8, minimumWidth), height: max(0, geometry.size.height - 8))
                        .padding(4)
                }
            }
            if !selection.items.isEmpty {
                HStack {
                    Text("Выбрано: \(selection.items.count)")
                    Button("Завершить принудительно…", role: .destructive) {
                        forceApps = apps.filter { selection.items.contains(.app($0.identity)) && $0.id > 1 && $0.id != ProcessInfo.processInfo.processIdentifier }
                        let covered = Set(forceApps.flatMap { $0.processes.map(\.id) })
                        var seen = covered
                        forceProcesses = apps.flatMap(\.processes).filter { selection.items.contains(.process($0.id)) && $0.pid > 1 && $0.pid != ProcessInfo.processInfo.processIdentifier && seen.insert($0.id).inserted }
                        confirmSelectionForceQuit = !forceApps.isEmpty || !forceProcesses.isEmpty
                    }
                    Spacer()
                    Button("Снять выделение") { selection = RowSelection(); selected = nil }
                        .buttonStyle(.plain)
                }.font(.caption).foregroundStyle(.secondary).padding(8)
                    .help("⌘-клик — несколько строк; Shift-клик — диапазон")
            }
            if let message = menuError ?? actions.message { Text(message).font(.caption).foregroundStyle(.orange).padding(6) }
        }
            .onChange(of: byCPU) { _, _ in overrideSort = nil }
            .alert("Завершить выбранное принудительно?", isPresented: $confirmSelectionForceQuit) {
                Button("Отмена", role: .cancel) {}
                Button("Завершить принудительно", role: .destructive) {
                    for app in forceApps { actions.forceQuit(app) }
                    for process in forceProcesses { actions.forceQuit(process) }
                }
            } message: { Text("Приложений: \(forceApps.count), отдельных процессов: \(forceProcesses.count). Несохранённые данные могут потеряться.") }
            .alert("Завершить принудительно?", isPresented: $confirmForceQuit, presenting: menuTarget) { app in
                Button("Отмена", role: .cancel) {}
                Button("Завершить принудительно", role: .destructive) { actions.forceQuit(app) }
            } message: { app in Text("\(app.name) будет завершено без сохранения. Несохранённые данные могут потеряться.") }
            .alert("Перезапустить приложение?", isPresented: $confirmRestart, presenting: menuTarget) { app in
                Button("Отмена", role: .cancel) {}
                Button("Перезапустить", role: .destructive) { actions.restart(app) }
            } message: { app in Text("\(app.name) будет закрыто обычным запросом и открыто заново. Сохрани документы перед продолжением.") }
            .alert("Завершить приложение?", isPresented: $confirmQuit, presenting: menuTarget) { app in
                Button("Отмена", role: .cancel) {}
                Button("Завершить", role: .destructive) { quit(app) }
            } message: { app in Text("Завершить \(app.name)? Сохрани документы перед продолжением.") }
    }
    private var header: some View {
        HStack(spacing: 10) {
            ForEach(columns) { column in
                Button {
                    if sorting.column == column { overrideSort = AppTableSort(column: column, ascending: !sorting.ascending) }
                    else { overrideSort = AppTableSort(column: column, ascending: column == .name || column == .pid) }
                } label: {
                    HStack(spacing: 4) {
                        if column != .name { Spacer(minLength: 0) }
                        Text(column.title)
                        if sorting.column == column { Image(systemName: sorting.ascending ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold)) }
                        if column == .name { Spacer(minLength: 0) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    .frame(width: column == .name ? nil : column.width, alignment: column == .name ? .leading : .trailing)
                    .frame(minWidth: column == .name ? column.width : nil, maxWidth: column == .name ? .infinity : nil)
                    .help(column.help + "\nНажми заголовок для сортировки; повторное нажатие меняет порядок.")
                    .accessibilityLabel("Сортировать: \(column.title)")
                    .accessibilityValue(sorting.column == column ? (sorting.ascending ? "По возрастанию" : "По убыванию") : "")
            }
            Color.clear.frame(width: 22, height: 1)
        }.padding(.horizontal, 10).frame(height: 34)
            .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 3)
    }
    private func appRow(_ app: AppUsage) -> some View {
        HStack(spacing: 10) {
            Button {
                if !expanded.insert(app.identity).inserted { expanded.remove(app.identity) }
            } label: {
                Image(systemName: expanded.contains(app.identity) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 24, height: 54).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(expanded.contains(app.identity) ? "Свернуть" : "Раскрыть") процессы \(app.name)")
            Button { selectRow(.app(app.identity)); selected = app.id } label: {
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
                        else { Image(systemName: "gearshape").frame(width: 28, height: 28).foregroundStyle(.secondary) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                            Text(detailed ? "PID \(app.id) · \(app.isBackground ? "фоновое" : "приложение")" : "PID \(app.id) · процессов: \(app.count)")
                                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }.frame(minWidth: AppColumn.name.width - 34, maxWidth: .infinity)
                    ForEach(columns.filter { $0 != .name }) { column in
                        Text(app.text(column)).font(.system(size: 14)).monospacedDigit().lineLimit(1).frame(width: column.width, alignment: .trailing)
                    }
                }.frame(height: 54).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Сводка приложения \(app.name)")
            Button { inspect(app.id) } label: { Image(systemName: "ellipsis.circle").font(.system(size: 15)).frame(width: 22, height: 36) }
                .buttonStyle(.borderless).help("Подробный инспектор \(app.name)")
        }.padding(.horizontal, 10).frame(height: 54).contentShape(Rectangle())
            .background(selection.items.contains(.app(app.identity)) ? Color.accentColor.opacity(0.13) : .clear)
            .contextMenu {
                contextMenu(app)
                if detailed {
                    Divider()
                    Menu("Столбцы", systemImage: "rectangle.split.3x1") {
                        ForEach(AppColumn.allCases.filter { $0 != .name }) { column in
                            Toggle(column.title, isOn: Binding(get: { visibleColumns.contains(column) }, set: { value in
                                if value { visibleColumns.insert(column) } else { visibleColumns.remove(column) }
                            }))
                        }
                    }
                }
            }
    }
    private func contextMenu(_ app: AppUsage) -> some View {
        ApplicationContextMenu(app: app, restartEnabled: actions.restarting == nil, inspect: {
            inspect(app.id)
        }, restart: { menuTarget = app; confirmRestart = true }, terminate: { menuTarget = app; confirmQuit = true }, forceQuit: { menuTarget = app; confirmForceQuit = true })
    }
    private func quit(_ app: AppUsage) { actions.terminateApplication(app) }
    private func detailedProcesses(_ app: AppUsage) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(orderedProcesses(app.processes, byCPU: sorting.column == .cpu)) { process in
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.turn.down.right").foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(process.pid == app.id ? "Основной процесс" : process.role == "Процесс" ? process.name : process.role).font(.system(size: 14, weight: .medium)).lineLimit(1)
                            Text(process.name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }.padding(.leading, 30).frame(minWidth: AppColumn.name.width, maxWidth: .infinity)
                    ForEach(columns.filter { $0 != .name }) { column in
                        Text(processText(process, column)).font(.system(size: 13)).monospacedDigit().lineLimit(1).frame(width: column.width, alignment: .trailing)
                    }
                    Color.clear.frame(width: 22, height: 1)
                }.padding(.horizontal, 10).frame(height: 50)
                    .background(selection.items.contains(.process(process.id)) ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.025))
                    .contentShape(Rectangle())
                    .onTapGesture { selectRow(.process(process.id)) }
                Divider().opacity(0.2)
            }
        }
    }
    private func selectRow(_ id: MonitorRowID) {
        let ordered = orderedApps.flatMap { app -> [MonitorRowID] in
            [.app(app.identity)] + (expanded.contains(app.identity) ? orderedProcesses(app.processes, byCPU: sorting.column == .cpu).map { .process($0.id) } : [])
        }
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        selection.select(id, ordered: ordered, extending: modifiers.contains(.shift), toggling: modifiers.contains(.command))
    }
    private func processText(_ process: ProcessRow, _ column: AppColumn) -> String {
        switch column {
        case .name: return process.name
        case .pid: return String(process.pid)
        case .cpu: return process.cpu.map { String(format: "%.1f%%", $0) } ?? "—"
        case .memory: return (process.footprint ?? process.memory).map(bytes) ?? "—"
        case .rss: return process.memory.map(bytes) ?? "—"
        case .processes: return "—"
        case .read: return rate(process.readRate)
        case .write: return rate(process.writeRate)
        case .uptime: return elapsedText(max(0, Date().timeIntervalSince1970 - Double(process.identity.seconds)))
        }
    }
}
