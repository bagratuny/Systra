import Foundation
import AppKit

struct ProcessIdentity: Hashable {
    let pid: Int32
    let seconds: UInt64
    let micros: UInt64
    var isCurrent: Bool { systra_same_process(pid, seconds, micros) != 0 }
}
struct ProcessSample {
    let identity: ProcessIdentity
    let parent: Int32
    var userID: UInt32 = getuid()
    let executable: String
    let arguments: String
    let cpuTime: UInt64?
    let memory: UInt64?
    var footprint: UInt64? = nil
    let disk: Counters?
}
struct ProcessSnapshot {
    let time: Double
    let rows: [ProcessSample]
}
struct ProcessRow: Identifiable {
    var id: ProcessIdentity { identity }
    let identity: ProcessIdentity
    var pid: Int32 { identity.pid }
    let parent: Int32
    var userID: UInt32 = getuid()
    let executable: String
    let role: String
    let cpu: Double?
    let memory: UInt64?
    var footprint: UInt64? = nil
    let readRate: Double?
    let writeRate: Double?
    let diskTotal: Counters?
    var name: String { URL(fileURLWithPath: executable).lastPathComponent }
}
struct AppUsage: Identifiable {
    let id: Int32
    let identity: ProcessIdentity
    let name: String
    let cpu: Double
    let memory: UInt64
    let count: Int
    let icon: NSImage?
    let bundleURL: URL?
    let processes: [ProcessRow]
    var isBackground = false
    var isUserOwned: Bool { processes.first(where: { $0.pid == id })?.userID == getuid() }
    var restartable: Bool { bundleURL != nil && id != ProcessInfo.processInfo.processIdentifier }
}
func processRole(executable: String, arguments: String) -> String {
    let name = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
    let args = arguments.lowercased()
    if args.contains("--type=renderer") { return args.contains("--extension-process") ? L("Расширение · renderer") : L("Renderer · веб-контент") }
    if args.contains("--type=gpu-process") { return L("GPU-процесс") }
    if args.contains("--utility-sub-type=network") { return L("Сетевая служба") }
    if args.contains("--utility-sub-type=audio") { return L("Аудиослужба") }
    if args.contains("--utility-sub-type=node") { return L("Node.js · служба") }
    if args.contains("--type=utility") { return L("Вспомогательная служба") }
    if name == "codex" || name == "claude" || name == "aider" || name == "opencode" { return L("AI-агент · {0}", String(describing: name)) }
    if name == "node" || name == "bun" || name == "deno" {
        if args.contains("mcp") { return "MCP · \(name)" }
        if args.contains("claude") || args.contains("codex") { return L("AI-инструмент · {0}", String(describing: name)) }
        return L("Среда выполнения · {0}", String(describing: name))
    }
    if name.contains("crashpad") { return L("Отчёты о сбоях") }
    if name.contains("renderer") { return "Renderer" }
    if name.contains("helper") { return L("Вспомогательный процесс") }
    return L("Процесс")
}
func collectProcesses() throws -> ProcessSnapshot {
    // Read argv only for role detection. Full command lines are never displayed or saved.
    var arguments: [Int32: String] = [:]
    if let text = try? systemOutput("/bin/ps", ["-ww", "-axo", "pid=,args="]) {
        for line in text.split(separator: "\n") {
            let fields = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            if fields.count == 2, let pid = Int32(fields[0]) { arguments[pid] = String(fields[1]) }
        }
    }
    var native = Array(repeating: SystraProcess(), count: 8192)
    let count = systra_processes(&native, Int32(native.count))
    guard count >= 0 else { throw NSError(domain: "Systra", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Не удалось прочитать список процессов")]) }
    let rows = native.prefix(Int(count)).map { native -> ProcessSample in
        var native = native
        let path = withUnsafeBytes(of: &native.executable) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
        return ProcessSample(identity: ProcessIdentity(pid: native.pid, seconds: native.startSeconds, micros: native.startMicroseconds),
            parent: native.parent, userID: native.uid, executable: path, arguments: arguments[native.pid] ?? "",
            cpuTime: native.hasUsage != 0 ? native.cpuNanoseconds : nil,
            memory: native.hasUsage != 0 ? native.resident : nil,
            footprint: native.hasDisk != 0 ? native.footprint : nil,
            disk: native.hasDisk != 0 ? Counters(input: native.readBytes, output: native.writtenBytes) : nil)
    }
    return ProcessSnapshot(time: ProcessInfo.processInfo.systemUptime, rows: rows)
}
func processRows(_ current: ProcessSnapshot, previous: ProcessSnapshot?) -> [ProcessRow] {
    let old = Dictionary(uniqueKeysWithValues: (previous?.rows ?? []).map { ($0.identity, $0) })
    let elapsed = current.time - (previous?.time ?? current.time)
    let valid = elapsed > 0 && elapsed < 15
    return current.rows.map { row in
        let before = old[row.identity]
        var cpu: Double?
        var read: Double?
        var write: Double?
        if valid, let value = row.cpuTime, let oldValue = before?.cpuTime, value >= oldValue {
            cpu = Double(value - oldValue) / elapsed / 1_000_000_000 * 100
        }
        if valid, let value = row.disk, let oldValue = before?.disk {
            if value.input >= oldValue.input { read = Double(value.input - oldValue.input) / elapsed }
            if value.output >= oldValue.output { write = Double(value.output - oldValue.output) / elapsed }
        }
        return ProcessRow(identity: row.identity, parent: row.parent, userID: row.userID, executable: row.executable,
            role: processRole(executable: row.executable, arguments: row.arguments), cpu: cpu, memory: row.memory, footprint: row.footprint,
            readRate: read, writeRate: write, diskTotal: row.disk)
    }
}

@MainActor final class AppActions: ObservableObject {
    @Published var restarting: Int32?
    @Published var message: String?
    func restart(_ usage: AppUsage) {
        guard restarting == nil, usage.restartable, usage.identity.isCurrent,
              let url = usage.bundleURL, let app = NSRunningApplication(processIdentifier: usage.id), app.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL else {
            message = L("Приложение уже завершилось или изменилось. Обнови выбор."); return
        }
        restarting = usage.id
        message = nil
        guard app.terminate() else { restarting = nil; message = L("Приложение отклонило запрос на завершение."); return }
        Task { @MainActor in
            for _ in 0..<120 {
                if app.isTerminated {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    config.createsNewApplicationInstance = true
                    do { _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config) }
                    catch { message = L("Приложение завершено, но не запустилось: {0}", String(describing: error.localizedDescription)) }
                    restarting = nil
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            restarting = nil
            message = L("Ожидание завершения истекло. Возможно, приложение ждёт сохранения документов. Повтори перезапуск после закрытия диалога.")
        }
    }
    func forceQuit(_ app: AppUsage) {
        guard app.id > 1, app.id != ProcessInfo.processInfo.processIdentifier, app.identity.isCurrent else {
            message = L("Приложение уже завершилось или изменилось. Обнови выбор."); return
        }
        message = nil
        if let running = NSRunningApplication(processIdentifier: app.id) {
            if !running.forceTerminate() { message = L("Не удалось принудительно завершить приложение.") }
        } else if kill(app.id, SIGKILL) != 0 { message = String(cString: strerror(errno)) }
    }
    func forceQuit(_ process: ProcessRow) {
        guard process.pid > 1, process.pid != ProcessInfo.processInfo.processIdentifier, process.identity.isCurrent else {
            message = L("Процесс уже завершился или изменился. Обнови выбор."); return
        }
        if kill(process.pid, SIGKILL) != 0 { message = String(cString: strerror(errno)) }
    }
    func terminateApplication(_ app: AppUsage) {
        guard app.id > 1, app.id != ProcessInfo.processInfo.processIdentifier, app.identity.isCurrent else {
            message = L("Приложение уже завершилось или изменилось. Обнови выбор."); return
        }
        if let running = NSRunningApplication(processIdentifier: app.id) {
            if !running.terminate() { message = L("Приложение отклонило запрос на завершение.") }
        } else if kill(app.id, SIGTERM) != 0 { message = String(cString: strerror(errno)) }
    }
    func terminate(_ process: ProcessRow) {
        guard process.pid > 1, process.pid != ProcessInfo.processInfo.processIdentifier, process.identity.isCurrent else {
            message = L("Процесс уже завершился или изменился. Обнови выбор."); return
        }
        if kill(process.pid, SIGTERM) != 0 { message = String(cString: strerror(errno)) }
    }
}
