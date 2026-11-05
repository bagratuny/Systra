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
                        .font(.system(size: 12)).foregroundStyle(.tertiary).frame(width: 14)
                    VStack(alignment: .leading, spacing: compact ? 3 : 1) {
                        Text(process.pid == app.id ? L("Основной процесс") : (process.role == L("Процесс") ? process.name : process.role))
                            .font(.system(size: compact ? 11 : 14, weight: .medium)).lineLimit(1)
                        Text(compact ? "PID \(process.pid)" : "\(process.name) · PID \(process.pid)")
                            .font(.system(size: compact ? 10 : 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 3)
                    Text(process.cpu.map { percent($0) } ?? "—")
                        .font(.system(size: compact ? 11 : 13)).monospacedDigit()
                        .foregroundStyle(.secondary).frame(width: compact ? 47 : 80, alignment: .trailing)
                    Text((process.footprint ?? process.memory).map(bytes) ?? "—")
                        .font(.system(size: compact ? 11 : 13, weight: .medium)).monospacedDigit()
                        .frame(width: compact ? 65 : 110, alignment: .trailing)
                }.padding(.vertical, compact ? 8 : 9).padding(.horizontal, compact ? 5 : 12)
                    .frame(maxWidth: .infinity).contentShape(Rectangle())
                    .background(selectedProcesses.contains(process.id) ? Color.accentColor.opacity(0.18) : .clear)
                    .onTapGesture { selectProcess?(process.id) }
                    .help(L("{0}\nCPU за интервал · память footprint", String(describing: process.executable)))
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
    @AppStorage("systra.columns.detailed") private var detailedColumnNames = "pid,cpu,memory,rss,processes,read,write,uptime"
    @AppStorage("systra.columns.compact") private var compactColumnNames = "cpu,memory"
    private var visibleColumns: Set<AppColumn> {
        Set((detailed ? detailedColumnNames : compactColumnNames).split(separator: ",").compactMap { AppColumn(rawValue: String($0)) })
    }
    private var availableColumns: [AppColumn] { detailed ? AppColumn.allCases.filter { $0 != .name } : [.cpu, .memory] }
    @State private var menuTarget: AppUsage?
    @State private var confirmRestart = false
    @State private var confirmQuit = false
    @State private var menuError: String?
    @StateObject private var actions = AppActions()
    private var sorting: AppTableSort {
        let preferred = overrideSort ?? AppTableSort(column: byCPU ? .cpu : .memory, ascending: false)
        if columns.contains(preferred.column) { return preferred }
        let fallback: AppColumn = columns.contains(.cpu) ? .cpu : columns.contains(.memory) ? .memory : .name
        return AppTableSort(column: fallback, ascending: fallback == .name)
    }
    private var columns: [AppColumn] { [.name] + availableColumns.filter { visibleColumns.contains($0) } }
    private var orderedApps: [AppUsage] { sortedApps(apps, by: sorting) }
    private var nameWidth: CGFloat { detailed ? AppColumn.name.width : 188 }
    private func columnWidth(_ column: AppColumn) -> CGFloat {
        if !detailed && column == .cpu { return 64 }
        if !detailed && column == .memory { return 88 }
        return column.width
    }
    private var minimumWidth: CGFloat { columns.reduce(0) { $0 + ($1 == .name ? nameWidth : columnWidth($1)) } + CGFloat(columns.count - 1) * 12 + 52 }
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                SystraScrollView(.horizontal) {
                    VStack(spacing: 8) {
                        header
                            .zIndex(1)
                        SystraScrollView(.vertical) {
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
                                if apps.isEmpty { Text(L("Ничего не найдено")).foregroundStyle(.secondary).padding(24) }
                            }
                        }
                    }.frame(width: max(geometry.size.width - 8, minimumWidth), height: max(0, geometry.size.height - 8))
                        .padding(4)
                }
            }
            if !selection.items.isEmpty {
                HStack {
                    Text(L("Выбрано: {0}", String(describing: selection.items.count)))
                    Button(L("Завершить принудительно…"), role: .destructive) {
                        forceApps = apps.filter { selection.items.contains(.app($0.identity)) && $0.id > 1 && $0.id != ProcessInfo.processInfo.processIdentifier }
                        let covered = Set(forceApps.flatMap { $0.processes.map(\.id) })
                        var seen = covered
                        forceProcesses = apps.flatMap(\.processes).filter { selection.items.contains(.process($0.id)) && $0.pid > 1 && $0.pid != ProcessInfo.processInfo.processIdentifier && seen.insert($0.id).inserted }
                        confirmSelectionForceQuit = !forceApps.isEmpty || !forceProcesses.isEmpty
                    }
                    Spacer()
                    Button(L("Снять выделение")) { selection = RowSelection(); selected = nil }
                        .buttonStyle(.plain)
                }.font(.caption).foregroundStyle(.secondary).padding(8)
                    .help(L("⌘-клик — несколько строк; Shift-клик — диапазон"))
            }
            if let message = menuError ?? actions.message { Text(message).font(.caption).foregroundStyle(.orange).padding(6) }
        }
            .onChange(of: byCPU) { _, _ in overrideSort = nil }
            .alert(L("Завершить выбранное принудительно?"), isPresented: $confirmSelectionForceQuit) {
                Button(L("Отмена"), role: .cancel) {}
                Button(L("Завершить принудительно"), role: .destructive) {
                    for app in forceApps { actions.forceQuit(app) }
                    for process in forceProcesses { actions.forceQuit(process) }
                }
            } message: { Text(L("Приложений: {0}, отдельных процессов: {1}. Несохранённые данные могут потеряться.", String(describing: forceApps.count), String(describing: forceProcesses.count))) }
            .alert(L("Завершить принудительно?"), isPresented: $confirmForceQuit, presenting: menuTarget) { app in
                Button(L("Отмена"), role: .cancel) {}
                Button(L("Завершить принудительно"), role: .destructive) { actions.forceQuit(app) }
            } message: { app in Text(L("{0} будет завершено без сохранения. Несохранённые данные могут потеряться.", String(describing: app.name))) }
            .alert(L("Перезапустить приложение?"), isPresented: $confirmRestart, presenting: menuTarget) { app in
                Button(L("Отмена"), role: .cancel) {}
                Button(L("Перезапустить"), role: .destructive) { actions.restart(app) }
            } message: { app in Text(L("{0} будет закрыто обычным запросом и открыто заново. Сохрани документы перед продолжением.", String(describing: app.name))) }
            .alert(L("Завершить приложение?"), isPresented: $confirmQuit, presenting: menuTarget) { app in
                Button(L("Отмена"), role: .cancel) {}
                Button(L("Завершить"), role: .destructive) { quit(app) }
            } message: { app in Text(L("Завершить {0}? Сохрани документы перед продолжением.", String(describing: app.name))) }
    }
    private var header: some View {
        HStack(spacing: 12) {
            ForEach(columns) { column in
                Button {
                    if sorting.column == column { overrideSort = AppTableSort(column: column, ascending: !sorting.ascending) }
                    else { overrideSort = AppTableSort(column: column, ascending: column == .name || column == .pid) }
                } label: {
                    HStack(spacing: 4) {
                        if column != .name { Spacer(minLength: 0) }
                        Text(column.title)
                        if sorting.column == column { Image(systemName: sorting.ascending ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .semibold)) }
                        if column == .name { Spacer(minLength: 0) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    .frame(width: column == .name ? nil : columnWidth(column), alignment: column == .name ? .leading : .trailing)
                    .frame(minWidth: column == .name ? nameWidth : nil, maxWidth: column == .name ? .infinity : nil)
                    .contextMenu { columnControls }
                    .help(column.help + L("\nНажми для сортировки. Правый клик — выбор столбцов."))
                    .accessibilityLabel(L("Сортировать: {0}", String(describing: column.title)))
                    .accessibilityValue(sorting.column == column ? (sorting.ascending ? L("По возрастанию") : L("По убыванию")) : "")
            }
            Color.clear.frame(width: 22, height: 1)
        }.padding(.horizontal, 12).frame(height: 36)
            .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 3)
            .contextMenu { columnControls }
    }
    private func appRow(_ app: AppUsage) -> some View {
        HStack(spacing: 12) {
            Button {
                if !expanded.insert(app.identity).inserted { expanded.remove(app.identity) }
            } label: {
                Image(systemName: expanded.contains(app.identity) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 24, height: 56).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(L("{0} процессы {1}", String(describing: expanded.contains(app.identity) ? L("Свернуть") : L("Раскрыть")), String(describing: app.name)))
            Button { selectRow(.app(app.identity)); selected = app.id } label: {
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
                        else { Image(systemName: "gearshape").frame(width: 28, height: 28).foregroundStyle(.secondary) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                            Text(detailed ? "PID \(app.id) · \(app.isBackground ? L("фоновое") : L("приложение"))" : L("PID {0} · процессов: {1}", String(describing: app.id), String(describing: app.count)))
                                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }.frame(minWidth: nameWidth - 34, maxWidth: .infinity)
                    ForEach(columns.filter { $0 != .name }) { column in
                        Text(app.text(column)).font(.system(size: 13)).monospacedDigit().lineLimit(1).frame(width: columnWidth(column), alignment: .trailing)
                    }
                }.frame(height: 56).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(L("Сводка приложения {0}", String(describing: app.name)))
            Button { inspect(app.id) } label: { Image(systemName: "info.circle").font(.system(size: 15)).frame(width: 22, height: 36) }
                .buttonStyle(.borderless).help(L("Подробный инспектор {0}", String(describing: app.name)))
        }.padding(.horizontal, 12).frame(height: 56).contentShape(Rectangle())
            .background(selection.items.contains(.app(app.identity)) ? Color.accentColor.opacity(0.13) : .clear)
            .contextMenu {
                contextMenu(app)
                Divider()
                Menu(L("Столбцы"), systemImage: "rectangle.split.3x1") { columnControls }
            }
    }
    private var columnControls: some View {
        Group {
            Toggle(AppColumn.name.title, isOn: .constant(true)).disabled(true)
            ForEach(availableColumns) { column in
                Toggle(column.title, isOn: Binding(get: { visibleColumns.contains(column) }, set: { shown in
                    var values = visibleColumns
                    if shown { values.insert(column) } else { values.remove(column) }
                    saveColumns(values)
                }))
            }
            Divider()
            Button(L("Восстановить столбцы")) { saveColumns(Set(availableColumns)) }
        }
    }
    private func saveColumns(_ values: Set<AppColumn>) {
        let encoded = availableColumns.filter { values.contains($0) }.map(\.rawValue).joined(separator: ",")
        if detailed { detailedColumnNames = encoded } else { compactColumnNames = encoded }
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
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.turn.down.right").foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(process.pid == app.id ? L("Основной процесс") : process.role == L("Процесс") ? process.name : process.role).font(.system(size: 14, weight: .medium)).lineLimit(1)
                            Text(process.name).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }.padding(.leading, 30).frame(minWidth: nameWidth, maxWidth: .infinity)
                    ForEach(columns.filter { $0 != .name }) { column in
                        Text(processText(process, column)).font(.system(size: 12)).monospacedDigit().lineLimit(1).frame(width: columnWidth(column), alignment: .trailing)
                    }
                    Color.clear.frame(width: 22, height: 1)
                }.padding(.horizontal, 12).frame(height: 52)
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
        case .cpu: return process.cpu.map { percent($0) } ?? "—"
        case .memory: return (process.footprint ?? process.memory).map(bytes) ?? "—"
        case .rss: return process.memory.map(bytes) ?? "—"
        case .processes: return "—"
        case .read: return rate(process.readRate)
        case .write: return rate(process.writeRate)
        case .uptime: return elapsedText(max(0, Date().timeIntervalSince1970 - Double(process.identity.seconds)))
        }
    }
}
