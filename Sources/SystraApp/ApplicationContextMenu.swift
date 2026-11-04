import SwiftUI
import AppKit

struct ApplicationContextMenu: View {
    let app: AppUsage
    var expanded: Bool? = nil
    var toggleExpansion: (() -> Void)? = nil
    var restartEnabled = true
    let inspect: () -> Void
    let restart: () -> Void
    let terminate: () -> Void
    let forceQuit: () -> Void
    var body: some View {
        if let expanded, let toggleExpansion {
            Button(expanded ? "Свернуть процессы" : "Раскрыть процессы", systemImage: "list.bullet.indent", action: toggleExpansion)
        }
        Button("Инспектор…", systemImage: "info.circle", action: inspect)
        Divider()
        Button("Показать приложение", systemImage: "macwindow") { NSRunningApplication(processIdentifier: app.id)?.activate(options: []) }.disabled(app.bundleURL == nil)
        Button("Показать в Finder", systemImage: "folder") {
            let url = app.bundleURL ?? app.processes.first(where: { $0.pid == app.id }).map { URL(fileURLWithPath: $0.executable) }
            if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        Menu("Скопировать", systemImage: "doc.on.doc") {
            Button("Имя") { copy(app.name) }
            Button("PID") { copy(String(app.id)) }
            Button("Путь") { copy(app.bundleURL?.path ?? app.processes.first(where: { $0.pid == app.id })?.executable ?? "") }
        }
        Divider()
        Button("Перезапустить…", systemImage: "arrow.clockwise", action: restart).disabled(!app.restartable || !restartEnabled)
        Button("Завершить…", systemImage: "xmark.circle", role: .destructive, action: terminate).disabled(app.id == ProcessInfo.processInfo.processIdentifier || app.id <= 1)
        Button("Завершить принудительно…", systemImage: "xmark.octagon", role: .destructive, action: forceQuit).disabled(app.id <= 1 || app.id == ProcessInfo.processInfo.processIdentifier)
    }
    private func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
}
