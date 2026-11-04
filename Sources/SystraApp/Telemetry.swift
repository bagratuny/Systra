import Foundation
import IOKit
import Metal

struct Counters: Equatable {
    var input: UInt64
    var output: UInt64
}
struct HardwareSnapshot {
    var time: Double = ProcessInfo.processInfo.systemUptime
    var disks: [String: Counters]?
    var network: [String: Counters]?
    var diskFree: UInt64?
    var diskTotal: UInt64?
    var gpu: Double?
    var gpuMemory: UInt64?
    var gpuName = "GPU"
    var temperatures: [TemperatureReading] = []
    var uptime = SystemUptimeSnapshot()
}

// A newly connected device establishes a baseline. Resets cannot produce negative rates.
func counterDelta(current: [String: Counters], previous: [String: Counters]) -> Counters {
    current.reduce(into: Counters(input: 0, output: 0)) { result, item in
        guard let old = previous[item.key] else { return }
        if item.value.input >= old.input { result.input += item.value.input - old.input }
        if item.value.output >= old.output { result.output += item.value.output - old.output }
    }
}

func systemOutput(_ path: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw NSError(domain: path, code: Int(process.terminationStatus)) }
    return String(decoding: data, as: UTF8.self)
}

func parseNetwork(_ text: String) -> [String: Counters]? {
    var result: [String: Counters] = [:]
    // Use only the link-layer row of physical Ethernet / Wi-Fi interfaces.
    // VPN, loopback, bridges, AirDrop are excluded to avoid counting traffic twice.
    var hasHeader = false
    for line in text.split(separator: "\n") {
        let columns = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if columns.first == "Name" { hasHeader = columns.contains("Ibytes") && columns.contains("Obytes"); continue }
        guard columns.count >= 10, columns[0].hasPrefix("en"), !columns[0].hasSuffix("*"), columns[2].hasPrefix("<Link#") else { continue }
        // Address may be absent; find byte columns relative to the end of the row.
        guard let input = UInt64(columns[columns.count - 5]), let output = UInt64(columns[columns.count - 2]) else { continue }
        result[columns[0]] = Counters(input: input, output: output)
    }
    return hasHeader ? result : nil
}

private func properties(_ service: io_object_t) -> [String: Any] {
    var value: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &value, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let retained = value?.takeRetainedValue() else { return [:] }
    return retained as NSDictionary as? [String: Any] ?? [:]
}

func collectHardware() -> HardwareSnapshot {
    var snapshot = HardwareSnapshot()
    var iterator: io_iterator_t = 0
    if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS {
        var disks: [String: Counters] = [:]
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            var identifier: UInt64 = 0
            let props = properties(service)
            if IORegistryEntryGetRegistryEntryID(service, &identifier) == KERN_SUCCESS,
               let stats = props["Statistics"] as? [String: Any],
               let input = stats["Bytes (Read)"] as? NSNumber, let output = stats["Bytes (Write)"] as? NSNumber {
                disks[String(identifier)] = Counters(input: input.uint64Value, output: output.uint64Value)
            }
        }
        IOObjectRelease(iterator)
        if !disks.isEmpty { snapshot.disks = disks }
    }
    let volume = URL(fileURLWithPath: NSHomeDirectory())
    if let values = try? volume.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]) {
        snapshot.diskTotal = values.volumeTotalCapacity.map { UInt64(max(0, $0)) }
        snapshot.diskFree = values.volumeAvailableCapacity.map { UInt64(max(0, $0)) }
    }
    if let text = try? systemOutput("/usr/sbin/netstat", ["-ibn"]) { snapshot.network = parseNetwork(text) }
    snapshot.gpuName = MTLCreateSystemDefaultDevice()?.name ?? "GPU"
    iterator = 0
    if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS {
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            let props = properties(service)
            if let stats = props["PerformanceStatistics"] as? [String: Any] {
                if let number = stats["Device Utilization %"] as? NSNumber {
                    let value = number.doubleValue
                    if value.isFinite && (0...100).contains(value) { snapshot.gpu = max(snapshot.gpu ?? 0, value) }
                }
                if let number = stats["In use system memory"] as? NSNumber { snapshot.gpuMemory = number.uint64Value }
            }
        }
        IOObjectRelease(iterator)
    }
    var readings = Array(repeating: SystraTemperature(), count: 256)
    let count = systra_temperatures(&readings, Int32(readings.count))
    if count > 0 {
        var occurrences: [String: Int] = [:]
        snapshot.temperatures = readings.prefix(Int(count)).map { reading in
            var reading = reading
            let name = withUnsafeBytes(of: &reading.name) { raw in
                String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            let occurrence = occurrences[name, default: 0]
            occurrences[name] = occurrence + 1
            return TemperatureReading(id: "\(name)-\(occurrence)", name: name, value: reading.celsius)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    snapshot.uptime = collectSystemUptime()
    snapshot.time = ProcessInfo.processInfo.systemUptime
    return snapshot
}

func rate(_ value: Double?) -> String {
    guard let value, value.isFinite, value >= 0 else { return "—" }
    return bytes(UInt64(min(value, Double(Int64.max)))) + "/с"
}
func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0) } ?? "—" }
func degrees(_ value: Double?) -> String { value.map { String(format: "%.1f °C", $0) } ?? "Недоступно" }
