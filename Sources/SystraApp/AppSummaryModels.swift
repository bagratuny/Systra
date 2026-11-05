import Foundation

struct AppTimelinePoint: Identifiable {
    let id = UUID()
    let date: Date
    let cpu: Double
    let memory: UInt64
}
enum ProcessCategory: String, CaseIterable, Identifiable {
    case tabs, extensions, main, gpu, network, agents, tools, other
    var id: String { rawValue }
    var title: String {
        switch self { case .tabs: return L("Веб-контент"); case .extensions: return L("Расширения"); case .main: return L("Основной процесс"); case .gpu: return "GPU"; case .network: return L("Сеть"); case .agents: return L("AI-агенты"); case .tools: return L("Инструменты / MCP"); case .other: return L("Прочие процессы") }
    }
    var symbol: String {
        switch self { case .tabs: return "rectangle.on.rectangle"; case .extensions: return "puzzlepiece.extension"; case .main: return "app"; case .gpu: return "square.3.layers.3d"; case .network: return "network"; case .agents: return "sparkles"; case .tools: return "wrench.and.screwdriver"; case .other: return "ellipsis.circle" }
    }
}
struct AppRoleGroup: Identifiable {
    var id: ProcessCategory { category }
    let category: ProcessCategory
    let count: Int
    let memory: UInt64
    let cpu: Double
}
func category(of process: ProcessRow, appPID: Int32) -> ProcessCategory {
    if process.pid == appPID { return .main }
    let role = process.role.lowercased(), name = process.name.lowercased()
    if (role.contains("расширение") || role.contains("extension")) || name.contains("extension") { return .extensions }
    if role.contains("renderer") || name.contains("webcontent") || name.contains("web content") { return .tabs }
    if role.contains("gpu") || name.contains("gpu") { return .gpu }
    if (role.contains("сетевая") || role.contains("network service")) || name.contains("networking") { return .network }
    if (role.contains("ai-агент") || role.contains("ai agent")) { return .agents }
    if role.contains("mcp") || (role.contains("среда выполнения") || role.contains("runtime")) || (role.contains("ai-инструмент") || role.contains("ai tool")) || role.contains("node.js") { return .tools }
    return .other
}
func appRoleGroups(_ app: AppUsage, byCPU: Bool) -> [AppRoleGroup] {
    let groups = Dictionary(grouping: app.processes) { category(of: $0, appPID: app.id) }
    return groups.map { category, processes in
        AppRoleGroup(category: category, count: processes.count,
            memory: processes.reduce(0) { $0 + ($1.footprint ?? $1.memory ?? 0) },
            cpu: processes.reduce(0) { $0 + ($1.cpu ?? 0) })
    }.sorted {
        let left = byCPU ? $0.cpu : Double($0.memory), right = byCPU ? $1.cpu : Double($1.memory)
        return left == right ? $0.category.rawValue < $1.category.rawValue : left > right
    }
}
