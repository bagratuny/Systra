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
            Button(expanded ? L("Свернуть процессы") : L("Раскрыть процессы"), systemImage: "list.bullet.indent", action: toggleExpansion)
        }
        Button(L("Инспектор…"), systemImage: "info.circle", action: inspect)
        Divider()
        Button(L("Показать приложение"), systemImage: "macwindow") { NSRunningApplication(processIdentifier: app.id)?.activate(options: []) }.disabled(app.bundleURL == nil)
        Button(L("Показать в Finder"), systemImage: "folder") {
            let url = app.bundleURL ?? app.processes.first(where: { $0.pid == app.id }).map { URL(fileURLWithPath: $0.executable) }
            if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        Menu(L("Скопировать"), systemImage: "doc.on.doc") {
            Button(L("Имя")) { copy(app.name) }
            Button("PID") { copy(String(app.id)) }
            Button(L("Путь")) { copy(app.bundleURL?.path ?? app.processes.first(where: { $0.pid == app.id })?.executable ?? "") }
        }
        Divider()
        Button(L("Перезапустить…"), systemImage: "arrow.clockwise", action: restart).disabled(!app.restartable || !restartEnabled)
        Button(L("Завершить…"), systemImage: "xmark.circle", role: .destructive, action: terminate).disabled(app.id == ProcessInfo.processInfo.processIdentifier || app.id <= 1)
        Button(L("Завершить принудительно…"), systemImage: "xmark.octagon", role: .destructive, action: forceQuit).disabled(app.id <= 1 || app.id == ProcessInfo.processInfo.processIdentifier)
    }
    private func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
}
