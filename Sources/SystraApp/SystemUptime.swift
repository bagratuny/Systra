import Foundation
import Darwin

func systemString(_ key: String) -> String? {
    var size = 0
    guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 1 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(cString: buffer)
}
func continuousSeconds() -> Double {
    var base = mach_timebase_info_data_t()
    mach_timebase_info(&base)
    return Double(mach_continuous_time()) * Double(base.numer) / Double(base.denom) / 1_000_000_000
}
func uptimeDuration(_ seconds: Double, compact: Bool = false) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "—" }
    let total = Int(min(seconds, Double(Int.max / 2)))
    let days = total / 86400, hours = total % 86400 / 3600, minutes = total % 3600 / 60, remainder = total % 60
    if compact {
        if days > 0 { return L("{0} д {1} ч", String(describing: days), String(describing: hours)) }
        if hours > 0 { return L("{0} ч {1} мин", String(describing: hours), String(describing: minutes)) }
        return L("{0} мин {1} с", String(describing: minutes), String(describing: remainder))
    }
    return L("{0} д {1} ч {2} мин {3} с", String(describing: days), String(describing: hours), String(describing: minutes), String(describing: remainder))
}
struct SystemInformation {
    let model = systemString("hw.model") ?? L("Неизвестно")
    let chip = systemString("machdep.cpu.brand_string") ?? L("Неизвестно")
    let kernel = systemString("kern.osrelease") ?? "—"
    let build = systemString("kern.osversion") ?? "—"
    let osVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()
    static let current = SystemInformation()
}
struct PowerStatistics {
    var sleep: Int?
    var darkWake: Int?
    var userWake: Int?
    static func parse(_ text: String) -> PowerStatistics {
        var result = PowerStatistics()
        for line in text.split(separator: "\n") {
            let pair = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, let count = Int(pair[1]), count >= 0 else { continue }
            switch pair[0] {
            case "Sleep Count": result.sleep = count
            case "Dark Wake Count": result.darkWake = count
            case "User Wake Count": result.userWake = count
            default: break
            }
        }
        return result
    }
}
private final class PowerStatisticsCache {
    static let shared = PowerStatisticsCache()
    private let lock = NSLock()
    private var updated: Double = -.infinity
    private var value = PowerStatistics()
    func read() -> PowerStatistics {
        lock.lock(); defer { lock.unlock() }
        let now = continuousSeconds()
        if now - updated >= 60 {
            value = (try? systemOutput("/usr/bin/pmset", ["-g", "stats"])).map(PowerStatistics.parse) ?? PowerStatistics()
            updated = now
        }
        return value
    }
}
struct SystemUptimeSnapshot {
    var includingSleep: Double = 0
    var awake: Double = 0
    var bootDate: Date?
    var load: [Double] = []
    var power = PowerStatistics()
    var sleeping: Double { max(0, includingSleep - awake) }
    var awakeFraction: Double { includingSleep > 0 ? min(1, max(0, awake / includingSleep)) : 0 }
}
func collectSystemUptime() -> SystemUptimeSnapshot {
    var snapshot = SystemUptimeSnapshot()
    // mach_continuous_time advances through sleep; systemUptime uses the uptime clock.
    snapshot.awake = ProcessInfo.processInfo.systemUptime
    snapshot.includingSleep = max(snapshot.awake, continuousSeconds())
    var boot = timeval(), size = MemoryLayout<timeval>.size
    if sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 {
        snapshot.bootDate = Date(timeIntervalSince1970: Double(boot.tv_sec) + Double(boot.tv_usec) / 1_000_000)
    }
    var load = [Double](repeating: 0, count: 3)
    if getloadavg(&load, 3) == 3 { snapshot.load = load }
    snapshot.power = PowerStatisticsCache.shared.read()
    return snapshot
}
