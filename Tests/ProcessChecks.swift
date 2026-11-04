import Foundation
import AppKit
func bytes(_ value: UInt64) -> String { String(value) }
@main struct Checks {
    static func main() throws {
        precondition(processRole(executable: "/Chrome Helper", arguments: "--type=renderer") == "Renderer · веб-контент")
        precondition(processRole(executable: "/Chrome Helper", arguments: "--type=renderer --extension-process") == "Расширение · renderer")
        precondition(processRole(executable: "/bin/codex", arguments: "app-server").contains("AI-агент"))
        precondition(processRole(executable: "/bin/node", arguments: "node /tmp/mcp/server.js").contains("MCP"))
        let oldIdentity = ProcessIdentity(pid: 12345, seconds: 1, micros: 0)
        let newIdentity = ProcessIdentity(pid: 12345, seconds: 2, micros: 0)
        let before = ProcessSample(identity: oldIdentity, parent: 1, executable: "test", arguments: "", cpuTime: 100, memory: 100, disk: Counters(input: 100, output: 100))
        let after = ProcessSample(identity: newIdentity, parent: 1, executable: "test", arguments: "", cpuTime: 10000, memory: 100, disk: Counters(input: 10000, output: 10000))
        let changed = processRows(ProcessSnapshot(time: 3, rows: [after]), previous: ProcessSnapshot(time: 1, rows: [before]))[0]
        precondition(changed.cpu == nil && changed.readRate == nil)
        let same = ProcessSample(identity: oldIdentity, parent: 1, executable: "test", arguments: "", cpuTime: 2_000_000_100, memory: 100, disk: Counters(input: 500, output: 700))
        let delta = processRows(ProcessSnapshot(time: 3, rows: [same]), previous: ProcessSnapshot(time: 1, rows: [before]))[0]
        precondition(delta.cpu == 100 && delta.readRate == 200 && delta.writeRate == 300)
        let sleeping = processRows(ProcessSnapshot(time: 40, rows: [same]), previous: ProcessSnapshot(time: 1, rows: [before]))[0]
        precondition(sleeping.cpu == nil && sleeping.readRate == nil)
        let busy = Process()
        busy.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
        busy.standardOutput = FileHandle.nullDevice
        busy.standardError = FileHandle.nullDevice
        try busy.run()
        defer { busy.terminate(); busy.waitUntilExit() }
        let first = try collectProcesses()
        usleep(1_500_000)
        let second = try collectProcesses()
        let row = processRows(second, previous: first).first { $0.pid == busy.processIdentifier }!
        precondition(row.identity.isCurrent && row.memory ?? 0 > 0)
        guard (row.cpu ?? 0) > 50 && (row.cpu ?? 0) < 130 else { throw NSError(domain: "CPUCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "CPU=\(String(describing: row.cpu))"]) }
        print("PASS: role detection, PID reuse protection, CPU and I/O deltas, sleep rebaseline; live single-core CPU=\(row.cpu!)%")
    }
}
