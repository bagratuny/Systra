import Foundation

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpu, memory, gpu, temperature, disk, network, uptime
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return L("Память")
        case .gpu: return "GPU"
        case .temperature: return L("Температура чипа")
        case .disk: return L("Диск · чтение и запись")
        case .network: return L("Сеть · загрузка и отдача")
        case .uptime: return L("Аптайм системы")
        }
    }
    static func load(from defaults: UserDefaults) -> Set<Self> {
        if let stored = defaults.string(forKey: "systra.menuMetrics") {
            return Set(stored.split(separator: ",").compactMap { Self(rawValue: String($0)) })
        }
        // Preserve the previous CPU toggle when upgrading from 0.9.0.
        return defaults.object(forKey: "systra.menuCPU") as? Bool == false ? [] : [.cpu]
    }
    static func encoded(_ metrics: Set<Self>) -> String {
        allCases.filter { metrics.contains($0) }.map(\.rawValue).joined(separator: ",")
    }
}

struct MenuBarReadings {
    var cpu: Double?
    var memory: UInt64?
    var gpu: Double?
    var temperature: Double?
    var diskRead: Double?
    var diskWrite: Double?
    var download: Double?
    var upload: Double?
    var uptime: Double?

    func text(for selection: Set<MenuBarMetric>) -> String {
        MenuBarMetric.allCases.filter { selection.contains($0) }.map { metric in
            switch metric {
            case .cpu: return "CPU " + percentage(cpu)
            case .memory: return "RAM " + (memory.map(bytes) ?? "—")
            case .gpu: return "GPU " + percentage(gpu)
            case .temperature: return temperature.map { decimal($0, digits: 0) + " °C" } ?? "— °C"
            case .disk: return L("Диск") + " ↓" + rate(diskRead) + " ↑" + rate(diskWrite)
            case .network: return L("Сеть") + " ↓" + rate(download) + " ↑" + rate(upload)
            case .uptime: return L("Аптайм") + " " + (uptime.map { uptimeDuration($0, compact: true) } ?? "—")
            }
        }.joined(separator: "  ·  ")
    }
    private func percentage(_ value: Double?) -> String {
        guard let value else { return "—" }
        return decimal(value, digits: 0) + "%"
    }
}
