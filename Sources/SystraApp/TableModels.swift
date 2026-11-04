import Foundation
import AppKit

enum AppColumn: String, CaseIterable, Identifiable {
    case name, pid, cpu, memory, rss, processes, read, write, uptime
    var id: String { rawValue }
    var title: String {
        switch self { case .name: return "Приложение / процесс"; case .pid: return "PID"; case .cpu: return "CPU"; case .memory: return "Память"; case .rss: return "RSS"; case .processes: return "Процессы"; case .read: return "Чтение/с"; case .write: return "Запись/с"; case .uptime: return "Время работы" }
    }
    var help: String {
        switch self {
        case .name:
            return "Имя приложения или процесса. Строка приложения объединяет показатели его процессов. Стрелка раскрывает процессы, нажатие на имя открывает сводку."
        case .pid:
            return "PID — идентификатор процесса в macOS. Для приложения показан PID основного процесса. После перезапуска он обычно меняется."
        case .cpu:
            return "Загрузка процессора за последний интервал обновления. 100% — одно полностью занятое ядро; несколько ядер могут дать больше 100%. Для приложения суммируются его процессы."
        case .memory:
            return "Память (footprint) — объём памяти, учитываемый macOS за процессом, включая сжатые страницы. Для приложения суммируются его процессы; если footprint недоступен, используется RSS. Общие страницы могут учитываться повторно."
        case .rss:
            return "RSS (Resident Set Size) — объём резидентных страниц процесса в физической RAM, без выгруженных в swap и сжатых страниц. Общие страницы могут входить в RSS нескольких процессов, поэтому сумма RSS не равна занятой RAM всего Mac."
        case .processes:
            return "Количество процессов в группе приложения: основной процесс, вспомогательные службы, renderer, агенты и другие дочерние процессы."
        case .read:
            return "Скорость чтения данных процессами с диска за последний интервал, в Б/с, KB/с или MB/с. Для приложения — сумма доступных счётчиков процессов. Может отличаться от физических операций SSD. «—» — данных пока нет."
        case .write:
            return "Скорость записи данных процессами на диск за последний интервал, в Б/с, KB/с или MB/с. Для приложения — сумма доступных счётчиков процессов. Может отличаться от физических операций SSD. «—» — данных пока нет."
        case .uptime:
            return "Время с запуска процесса. Для приложения отсчитывается от запуска основного процесса; его вспомогательные процессы могут быть запущены позже."
        }
    }
    var width: CGFloat {
        switch self { case .name: return 230; case .pid: return 65; case .cpu: return 75; case .memory, .rss: return 100; case .processes: return 80; case .read, .write: return 100; case .uptime: return 100 }
    }
}
struct AppTableSort: Equatable {
    var column: AppColumn
    var ascending: Bool
}
extension AppUsage {
    var residentMemory: UInt64? {
        let values = processes.compactMap(\.memory)
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    var readBytesPerSecond: Double? {
        let values = processes.compactMap(\.readRate)
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    var writeBytesPerSecond: Double? {
        let values = processes.compactMap(\.writeRate)
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    var elapsedSeconds: Double { max(0, Date().timeIntervalSince1970 - Double(identity.seconds)) }
    func numericValue(_ column: AppColumn) -> Double? {
        switch column {
        case .name: return nil
        case .pid: return Double(id)
        case .cpu: return cpu
        case .memory: return Double(memory)
        case .rss: return residentMemory.map(Double.init)
        case .processes: return Double(count)
        case .read: return readBytesPerSecond
        case .write: return writeBytesPerSecond
        case .uptime: return elapsedSeconds
        }
    }
    func text(_ column: AppColumn) -> String {
        switch column {
        case .name: return name
        case .pid: return String(id)
        case .cpu: return String(format: "%.1f%%", cpu)
        case .memory: return bytes(memory)
        case .rss: return residentMemory.map(bytes) ?? "—"
        case .processes: return String(count)
        case .read: return rate(readBytesPerSecond)
        case .write: return rate(writeBytesPerSecond)
        case .uptime: return elapsedText(elapsedSeconds)
        }
    }
}
func elapsedText(_ seconds: Double) -> String {
    let value = Int(max(0, seconds))
    if value >= 86400 { return "\(value / 86400) д \(value % 86400 / 3600) ч" }
    if value >= 3600 { return "\(value / 3600) ч \(value % 3600 / 60) м" }
    if value >= 60 { return "\(value / 60) м \(value % 60) с" }
    return "\(value) с"
}
func sortedApps(_ apps: [AppUsage], by sort: AppTableSort) -> [AppUsage] {
    apps.sorted { lhs, rhs in
        if sort.column == .name {
            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order != .orderedSame { return sort.ascending ? order == .orderedAscending : order == .orderedDescending }
        } else {
            let left = lhs.numericValue(sort.column), right = rhs.numericValue(sort.column)
            // Missing counters remain last in either direction.
            if left == nil && right != nil { return false }
            if left != nil && right == nil { return true }
            if let left, let right, left != right { return sort.ascending ? left < right : left > right }
        }
        return lhs.id < rhs.id
    }
}
extension ProcessRow {
    var cpuSortValue: Double { cpu ?? -1 }
    var memorySortValue: UInt64 { footprint ?? memory ?? 0 }
    var rssSortValue: UInt64 { memory ?? 0 }
    var readSortValue: Double { readRate ?? -1 }
    var writeSortValue: Double { writeRate ?? -1 }
}

struct ApplicationsSummary {
    let rows: [AppUsage]
    var appCount: Int { rows.filter { $0.bundleURL != nil }.count }
    var serviceCount: Int { rows.count - appCount }
    var processCount: Int { rows.reduce(0) { $0 + $1.count } }
    var cpu: Double { rows.reduce(0) { $0 + $1.cpu } }
    var memory: UInt64 { rows.reduce(0) { $0 + $1.memory } }
    var read: Double? { sum(rows.compactMap(\.readBytesPerSecond)) }
    var write: Double? { sum(rows.compactMap(\.writeBytesPerSecond)) }
    var disk: Double? { sum([read, write].compactMap { $0 }) }
    var cpuLeader: AppUsage? { sortedApps(rows, by: AppTableSort(column: .cpu, ascending: false)).first }
    var memoryLeader: AppUsage? { sortedApps(rows, by: AppTableSort(column: .memory, ascending: false)).first }
    private func sum(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) }
}
