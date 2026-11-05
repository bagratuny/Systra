import Foundation

@MainActor private final class FakeLoginService: LoginItemService {
    var state: LoginItemState = .disabled
    var registers = 0, unregisters = 0
    var nextState: LoginItemState = .enabled
    var fail = false
    func register() throws {
        registers += 1
        if fail { throw NSError(domain: "test", code: 1) }
        state = nextState
    }
    func unregister() throws {
        unregisters += 1
        if fail { throw NSError(domain: "test", code: 2) }
        state = .disabled
    }
}
@main struct MenuBarSettingsChecks {
    @MainActor static func main() {
        let suite = "Systra.Checks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(MenuBarMetric.load(from: defaults) == [.cpu])
        defaults.set(false, forKey: "systra.menuCPU")
        precondition(MenuBarMetric.load(from: defaults).isEmpty)
        defaults.set("memory,cpu,obsolete,memory", forKey: "systra.menuMetrics")
        precondition(MenuBarMetric.load(from: defaults) == [.cpu, .memory])
        precondition(MenuBarMetric.encoded(MenuBarMetric.load(from: defaults)) == "cpu,memory")
        defaults.set("", forKey: "systra.menuMetrics")
        precondition(MenuBarMetric.load(from: defaults).isEmpty, "An explicit empty choice must stay icon-only")
        let readings = MenuBarReadings(cpu: 25, memory: 1024, gpu: 12, temperature: 45, diskRead: 2048, diskWrite: 1024, download: 4096, upload: 512, uptime: 90061)
        precondition(readings.text(for: []).isEmpty)
        precondition(readings.text(for: [.gpu, .cpu]) == "CPU 25%  ·  GPU 12%")
        precondition(MenuBarReadings().text(for: [.cpu, .memory, .gpu]) == "CPU —  ·  RAM —  ·  GPU —")
        precondition(readings.text(for: Set(MenuBarMetric.allCases)).components(separatedBy: "  ·  ").count == 7)
        precondition(readings.text(for: [.disk]).contains("↓") && readings.text(for: [.network]).contains("↑"))
        let service = FakeLoginService()
        let settings = LoginItemSettings(service: service)
        precondition(!settings.isRequested && service.registers == 0)
        settings.setEnabled(true)
        precondition(settings.state == .enabled && settings.error == nil)
        settings.setEnabled(true)
        precondition(service.registers == 1, "Do not register an already registered item")
        settings.setEnabled(false)
        precondition(settings.state == .disabled && service.unregisters == 1)
        service.fail = true
        settings.setEnabled(true)
        precondition(settings.state == .disabled && settings.error != nil, "A registration failure must not look enabled")
        service.fail = false
        service.nextState = .requiresApproval
        settings.setEnabled(true)
        precondition(settings.isRequested && settings.state == .requiresApproval && settings.error == nil)
        settings.setEnabled(false)
        precondition(!settings.isRequested, "Pending registration must be cancellable")
        service.state = .enabled
        settings.refresh()
        precondition(settings.state == .enabled, "Reflect changes made in System Settings")
        service.fail = true
        settings.setEnabled(false)
        precondition(settings.state == .enabled && settings.error != nil, "Unregister failures must keep actual state")
        print("PASS: menu selection migration, persistence, deterministic readouts, missing samples; login item registration, approval, cancellation and failure state")
    }
}
