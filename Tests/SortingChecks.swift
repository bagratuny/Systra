import Foundation
import AppKit
@main struct SortingChecks {
    static func process(_ pid: Int32, memory: UInt64?, footprint: UInt64?, read: Double?) -> ProcessRow {
        ProcessRow(identity: ProcessIdentity(pid: pid, seconds: 100, micros: 0), parent: 1, executable: "/test/process", role: "Процесс", cpu: 10, memory: memory, footprint: footprint, readRate: read, writeRate: read, diskTotal: nil)
    }
    static func app(_ pid: Int32, name: String, memory: UInt64, cpu: Double, members: [ProcessRow]) -> AppUsage {
        AppUsage(id: pid, identity: ProcessIdentity(pid: pid, seconds: 100, micros: 0), name: name, cpu: cpu, memory: memory, count: members.count, icon: nil, bundleURL: nil, processes: members)
    }
    static func main() {
        precondition(MetricDisplayUnit.temperature.formatted(44.4) == "44,4 °C")
        precondition(MetricDisplayUnit.percentage.formatted(44.4) == "44,4%")
        precondition(MetricDisplayUnit.throughput.formatted(1024) == "1,0 КБ/с")
        precondition(percent(25.5) == "25,5%" && percent(nil) == "—")
        precondition(bytes(1024) == "1,0 КБ" && bytes(0) == "0 Б")
        precondition(degrees(36.5) == "36,5 °C" && rate(nil) == "—")
        precondition(decimal(.infinity) == "—")
        let first = app(10, name: "Alpha", memory: 3_000_000_000, cpu: 9, members: [process(10, memory: 100, footprint: 1000, read: 0), process(11, memory: 200, footprint: 2000, read: 50)])
        let second = app(20, name: "beta", memory: 800_000_000, cpu: 100, members: [process(20, memory: 900, footprint: 900, read: 100)])
        let unknown = app(30, name: "Gamma", memory: 0, cpu: 9, members: [process(30, memory: nil, footprint: nil, read: nil)])
        let input = [second, unknown, first]
        precondition(sortedApps(input, by: AppTableSort(column: .memory, ascending: true)).map(\.id) == [30,20,10])
        precondition(sortedApps(input, by: AppTableSort(column: .cpu, ascending: false)).map(\.id) == [20,10,30])
        precondition(sortedApps(input, by: AppTableSort(column: .name, ascending: true)).map(\.id) == [10,20,30])
        precondition(sortedApps(input, by: AppTableSort(column: .name, ascending: false)).map(\.id) == [30,20,10])
        precondition(sortedApps(input, by: AppTableSort(column: .read, ascending: true)).map(\.id) == [10,20,30])
        precondition(sortedApps(input, by: AppTableSort(column: .read, ascending: false)).map(\.id) == [20,10,30])
        precondition(first.residentMemory == 300 && first.readBytesPerSecond == 50 && first.writeBytesPerSecond == 50)
        precondition(unknown.residentMemory == nil && unknown.readBytesPerSecond == nil)
        precondition(first.elapsedSeconds >= 0)
        let processRows = first.processes.sorted(using: [KeyPathComparator(\ProcessRow.memorySortValue, order: .reverse)])
        precondition(processRows.map(\.pid) == [11,10])
        precondition(uptimeDuration(90061) == "1 д 1 ч 1 мин 1 с")
        precondition(uptimeDuration(90061, compact: true) == "1 д 1 ч")
        precondition(uptimeDuration(.nan) == "—")
        let power = PowerStatistics.parse("Sleep Count:70\nDark Wake Count:68\nUser Wake Count:4\nNoise:99")
        precondition(power.sleep == 70 && power.darkWake == 68 && power.userWake == 4)
        precondition(PowerStatistics.parse("Sleep Count:-1\nUser Wake Count:invalid").sleep == nil)
        let system = collectSystemUptime()
        precondition(system.bootDate != nil && system.includingSleep >= system.awake && system.sleeping >= 0 && system.load.count == 3)
        precondition(system.awakeFraction >= 0 && system.awakeFraction <= 1)
        print("PASS: uptime formatting, sleep counters, native boot date, clocks and load averages")
        let summary = ApplicationsSummary(rows: input)
        precondition(summary.processCount == 4 && summary.appCount == 0 && summary.serviceCount == 3)
        precondition(summary.cpu == 118 && summary.memory == 3_800_000_000)
        precondition(summary.read == 150 && summary.disk == 300)
        precondition(summary.cpuLeader?.id == 20 && summary.memoryLeader?.id == 10)
        let empty = ApplicationsSummary(rows: [])
        precondition(empty.processCount == 0 && empty.cpu == 0 && empty.memory == 0 && empty.disk == nil && empty.cpuLeader == nil)
        precondition(ApplicationsSummary(rows: [unknown]).disk == nil)
        print("PASS: numeric/name sorting, both directions, missing counters, deterministic ties, aggregated RSS/I/O and process column comparators")
    }
}
