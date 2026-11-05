import Foundation
import AppKit
@main struct AppSummaryChecks {
    static func process(_ pid: Int32, name: String, role: String, memory: UInt64?, footprint: UInt64?, cpu: Double?) -> ProcessRow {
        ProcessRow(identity: ProcessIdentity(pid: pid, seconds: 1, micros: 0), parent: 10, executable: "/test/" + name, role: role, cpu: cpu, memory: memory, footprint: footprint, readRate: nil, writeRate: nil, diskTotal: nil)
    }
    static func main() {
        let members = [
            process(10, name: "Chrome", role: "Процесс", memory: 40, footprint: 200, cpu: 1),
            process(11, name: "Helper", role: "Renderer · веб-контент", memory: 10, footprint: 100, cpu: 20),
            process(12, name: "Helper", role: "Расширение · renderer", memory: 10, footprint: 30, cpu: 10),
            process(13, name: "Helper", role: "GPU-процесс", memory: 10, footprint: 50, cpu: 2),
            process(14, name: "Helper", role: "Сетевая служба", memory: 10, footprint: 20, cpu: 1),
            process(15, name: "codex", role: "AI-агент · codex", memory: 10, footprint: 60, cpu: 3),
            process(16, name: "node", role: "MCP · node", memory: 10, footprint: 45, cpu: 2),
            process(17, name: "service", role: "Процесс", memory: 80, footprint: nil, cpu: nil)]
        let app = AppUsage(id: 10, identity: members[0].identity, name: "Chrome", cpu: 39, memory: 585, count: members.count, icon: nil, bundleURL: nil, processes: members)
        let memoryGroups = appRoleGroups(app, byCPU: false)
        precondition(memoryGroups.count == 8)
        precondition(memoryGroups.first?.category == .main)
        precondition(memoryGroups.reduce(0) { $0 + $1.memory } == 585)
        precondition(memoryGroups.reduce(0) { $0 + $1.count } == members.count)
        precondition(memoryGroups.reduce(0) { $0 + $1.cpu } == 39)
        precondition(appRoleGroups(app, byCPU: true).first?.category == .tabs)
        precondition(category(of: members[2], appPID: 10) == .extensions)
        precondition(category(of: members[0], appPID: 10) == .main)
        precondition(category(of: process(18, name: "Safari Web Content", role: "Процесс", memory: nil, footprint: nil, cpu: nil), appPID: 10) == .tabs)
        let englishRoles: [(String, ProcessCategory)] = [("Extension · renderer", .extensions), ("Renderer · web content", .tabs), ("Network service", .network), ("AI agent · codex", .agents), ("Runtime · node", .tools), ("AI tool · bun", .tools)]
        for (role, expected) in englishRoles {
            precondition(category(of: process(19, name: "helper", role: role, memory: nil, footprint: nil, cpu: nil), appPID: 10) == expected)
        }
        print("PASS: sidebar categories, mutually exclusive groups, footprint fallback, CPU/memory totals and ranking")
    }
}
