import AppKit
import SwiftUI
import Darwin
import Combine

struct Sample: Identifiable {
    let id = UUID()
    let value: Double
}
@MainActor final class Monitor: ObservableObject {
    @Published var hardware = HardwareSnapshot()
    let sessionStartedAt = Date()
    let sessionStartClock = continuousSeconds()
    @Published var lastWakeDate: Date?
    @Published var lastSleepDate: Date?
    private var uptimeObservers = Set<AnyCancellable>()
    @Published var diskRead: Double?
    @Published var diskWrite: Double?
    @Published var download: Double?
    @Published var upload: Double?
    @Published var sessionRead: UInt64 = 0
    @Published var sessionWritten: UInt64 = 0
    @Published var sessionReceived: UInt64 = 0
    @Published var sessionSent: UInt64 = 0
    private var previousHardware: HardwareSnapshot?
    private var previousProcesses: ProcessSnapshot?
    var chipTemperature: Double? {
        hardware.temperatures.filter { $0.component == .chip || $0.component == .cpu || $0.component == .gpu }.map(\.value).max()
    }
    var batteryTemperature: Double? {
        hardware.temperatures.filter { $0.component == .battery }.map(\.value).max()
    }
    @Published var cpu: Double = 0
    @Published var inspectionRequest: Int32?
    @Published var summaryRequest: Int32?
    @Published var appHistory: [ProcessIdentity: [AppTimelinePoint]] = [:]
    @Published var appMemory: UInt64 = 0
    @Published var wiredMemory: UInt64 = 0
    @Published var compressedMemory: UInt64 = 0
    @Published var cachedMemory: UInt64 = 0
    @Published var pressure: Int32 = 0
    @Published var metricHistory: [String: [Sample]] = [:]
    @Published var usedMemory: UInt64 = 0
    @Published var swap: UInt64 = 0
    @Published var apps: [AppUsage] = []
    @Published var history: [Sample] = []
    @Published var updated: Date?
    @Published var error: String?
    let totalMemory = ProcessInfo.processInfo.physicalMemory
    private var previousTicks: [UInt64]?
    private var timer: Timer?
    private var collecting = false
    var statusChanged: ((Double) -> Void)?

    func start() {
        let notifications = NSWorkspace.shared.notificationCenter
        notifications.publisher(for: NSWorkspace.didWakeNotification).receive(on: RunLoop.main).sink { [weak self] _ in self?.lastWakeDate = Date() }.store(in: &uptimeObservers)
        notifications.publisher(for: NSWorkspace.willSleepNotification).receive(on: RunLoop.main).sink { [weak self] _ in self?.lastSleepDate = Date() }.store(in: &uptimeObservers)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func refresh() {
        readCPU()
        readMemory()
        guard !collecting else { return }
        collecting = true
        let running = NSWorkspace.shared.runningApplications
        DispatchQueue.global(qos: .utility).async {
            let hardware = collectHardware()
            Task { @MainActor in self.acceptHardware(hardware) }
            do {
                let snapshot = try collectProcesses()
                Task { @MainActor in self.accept(snapshot, running: running); self.collecting = false }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in self.error = message; self.collecting = false }
            }
        }
    }
    private func acceptHardware(_ snapshot: HardwareSnapshot) {
        defer {
            hardware = snapshot; previousHardware = snapshot
            appendMetric("memory", Double(usedMemory) / Double(totalMemory) * 100)
            if let gpu = snapshot.gpu { appendMetric("gpu", gpu) }
            if let temperature = snapshot.temperatures.filter({ $0.component == .chip || $0.component == .cpu || $0.component == .gpu }).map(\.value).max() { appendMetric("temperature", temperature) }
            if let value = diskRead { appendMetric("disk", value + (diskWrite ?? 0)) }
            if let value = download { appendMetric("network", value + (upload ?? 0)) }
        }
        guard let previous = previousHardware else { return }
        let elapsed = snapshot.time - previous.time
        guard elapsed > 0 else { return }
        // Re-baseline after sleep; omit the interval rather than reporting misleading rates.
        guard elapsed < 15 else {
            diskRead = nil; diskWrite = nil; download = nil; upload = nil
            return
        }
        if let current = snapshot.disks, let old = previous.disks {
            let delta = counterDelta(current: current, previous: old)
            diskRead = Double(delta.input) / elapsed; diskWrite = Double(delta.output) / elapsed
            sessionRead += delta.input; sessionWritten += delta.output
        } else { diskRead = nil; diskWrite = nil }
        if let current = snapshot.network, let old = previous.network {
            let delta = counterDelta(current: current, previous: old)
            download = current.isEmpty ? nil : Double(delta.input) / elapsed
            upload = current.isEmpty ? nil : Double(delta.output) / elapsed
            sessionReceived += delta.input; sessionSent += delta.output
        } else { download = nil; upload = nil }
    }
    private func accept(_ snapshot: ProcessSnapshot, running: [NSRunningApplication]) {
        let rows = processRows(snapshot, previous: previousProcesses)
        previousProcesses = snapshot
        let byPID = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) })
        let visible = running.filter {
            guard let path = $0.bundleURL?.path else { return false }
            return !path.contains("/Contents/")
        }
        let appByPID = Dictionary(uniqueKeysWithValues: visible.map { ($0.processIdentifier, $0) })
        var groups: [Int32: [ProcessRow]] = [:]
        for row in rows {
            var cursor = row.pid
            var owner: Int32?
            var seen = Set<Int32>()
            while cursor > 1 && seen.insert(cursor).inserted {
                if appByPID[cursor] != nil { owner = cursor; break }
                guard let ancestor = byPID[cursor] else { break }
                cursor = ancestor.parent
            }
            if owner == nil {
                owner = visible.first(where: { app in
                    guard let path = app.bundleURL?.path else { return false }
                    return row.executable.hasPrefix(path + "/")
                })?.processIdentifier
            }
            groups[owner ?? row.pid, default: []].append(row)
        }
        apps = groups.compactMap { pid, members in
            guard let root = byPID[pid] else { return nil }
            let app = appByPID[pid]
            return AppUsage(id: pid, identity: root.identity, name: app?.localizedName ?? root.name,
                cpu: members.reduce(0) { $0 + ($1.cpu ?? 0) }, memory: members.reduce(0) { $0 + ($1.footprint ?? $1.memory ?? 0) },
                count: members.count, icon: pid == ProcessInfo.processInfo.processIdentifier ? (SystraIcons.small ?? NSApp.applicationIconImage) : app?.icon, bundleURL: app?.bundleURL, processes: members, isBackground: app?.activationPolicy != .regular)
        }
        let now = Date()
        var timelines = appHistory.filter { ($0.value.last?.date ?? .distantPast) > now.addingTimeInterval(-120) }
        for app in apps {
            var points = timelines[app.identity, default: []]
            points.append(AppTimelinePoint(date: now, cpu: app.cpu, memory: app.memory))
            if points.count > 60 { points.removeFirst(points.count - 60) }
            timelines[app.identity] = points
        }
        appHistory = timelines
        updated = now; error = nil
    }
    private func appendMetric(_ name: String, _ value: Double) {
        var samples = metricHistory[name, default: []]
        samples.append(Sample(value: value))
        if samples.count > 60 { samples.removeFirst(samples.count - 60) }
        metricHistory[name] = samples
    }
    private func readCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let ticks = [UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1), UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3)]
        defer { previousTicks = ticks }
        guard let previous = previousTicks else { return }
        let delta = zip(ticks, previous).map { $0 >= $1 ? $0 - $1 : 0 }
        let total = delta.reduce(0, +)
        guard total > 0 else { return }
        cpu = 100 * Double(total - delta[2]) / Double(total)
        history.append(Sample(value: cpu))
        if history.count > 60 { history.removeFirst(history.count - 60) }
        statusChanged?(cpu)
    }
    private func readMemory() {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let internalPages = UInt64(vm.internal_page_count)
            let purgeable = UInt64(vm.purgeable_count)
            appMemory = (internalPages - min(internalPages, purgeable)) * page
            wiredMemory = UInt64(vm.wire_count) * page
            compressedMemory = UInt64(vm.compressor_page_count) * page
            cachedMemory = (UInt64(vm.external_page_count) + purgeable) * page
            usedMemory = min(totalMemory, appMemory + wiredMemory + compressedMemory)
            var level: Int32 = 0
            var levelSize = MemoryLayout<Int32>.size
            pressure = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0 ? level : 0
        }
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 { swap = usage.xsu_used }
    }
}

func bytes(_ value: UInt64) -> String {
    if value == 0 { return "0 Б" }
    return ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let progress: Double
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 32, weight: .medium, design: .rounded)).monospacedDigit()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.13))
                    Capsule().fill(color).frame(width: geo.size.width * min(1, max(0, progress)))
                }
            }.frame(height: 5)
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSToolbarDelegate, NSSearchFieldDelegate {
    private let monitor = Monitor()
    private let navigation = WindowNavigation()
    private var toolbarSubscriptions = Set<AnyCancellable>()
    private var window: NSWindow!
    private var status: NSStatusItem!
    private let popover = NSPopover()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.main.url(forResource: "Systra", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Systra")
        let metricsItem = applicationMenu.addItem(withTitle: "Показатели в строке меню", action: #selector(togglePopover), keyEquivalent: "p")
        metricsItem.keyEquivalentModifierMask = [.command, .shift]
        metricsItem.target = self
        applicationMenu.addItem(withTitle: "Открыть монитор", action: #selector(show), keyEquivalent: "o").target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Выйти из Systra", action: #selector(quit), keyEquivalent: "q").target = self
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "Файл")
        fileMenu.addItem(withTitle: "Закрыть окно", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)
        NSApp.mainMenu = mainMenu
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = featherMenuBarIcon()
        status.button?.imagePosition = .imageLeading
        status.button?.title = " —"
        status.button?.target = self
        status.button?.action = #selector(togglePopover)
        status.button?.toolTip = "Systra — показатели Mac"
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 430, height: 650)
        popover.contentViewController = NSHostingController(rootView: PopoverDashboard(monitor: monitor, openWindow: { [weak self] in self?.show() }, quit: { [weak self] in self?.quit() }, openApp: { [weak self] pid in self?.monitor.inspectionRequest = pid; self?.show() }, openSummary: { [weak self] pid in self?.monitor.summaryRequest = pid; self?.show() }).preferredColorScheme(.dark).background(Color(red: 0.13, green: 0.135, blue: 0.145)))
        monitor.statusChanged = { [weak self] cpu in self?.status.button?.title = String(format: " %.0f%%", cpu) }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 740),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.delegate = self
        window.title = "Systra — монитор Mac"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        let toolbar = NSToolbar(identifier: "Systra.MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        toolbar.centeredItemIdentifier = .init("Systra.Tabs")
        window.toolbar = toolbar
        window.contentView = NSHostingView(rootView: Dashboard(monitor: monitor, navigation: navigation))
        window.isReleasedWhenClosed = false
        window.center()
        show()
        monitor.start()
        if CommandLine.arguments.contains("--self-check") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in
                let healthy = monitor.updated != nil && !monitor.apps.isEmpty && monitor.usedMemory > 0 && monitor.history.count >= 2 && monitor.diskRead != nil && monitor.download != nil && monitor.hardware.gpu != nil && !monitor.hardware.temperatures.isEmpty
                print("Systra check: \(healthy ? "PASS" : "FAIL"); CPU=\(monitor.cpu); memory=\(monitor.usedMemory); groups=\(monitor.apps.count); samples=\(monitor.history.count)")
                print("Hardware: disk=\(rate(monitor.diskRead))/\(rate(monitor.diskWrite)); network=\(rate(monitor.download))/\(rate(monitor.upload)); GPU=\(percent(monitor.hardware.gpu)); chip=\(degrees(monitor.chipTemperature)); sensors=\(monitor.hardware.temperatures.count)")
                exit(healthy ? 0 : 1)
            }
        }
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("Systra.Brand"), .init("Systra.Tabs"), .init("Systra.Search"), .flexibleSpace]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("Systra.Brand"), .flexibleSpace, .init("Systra.Tabs"), .flexibleSpace, .init("Systra.Search")]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier.rawValue == "Systra.Search" {
            let item = NSSearchToolbarItem(itemIdentifier: identifier)
            item.label = "Поиск приложений"
            item.preferredWidthForSearchField = 180
            item.resignsFirstResponderWithCancel = true
            item.searchField.placeholderString = "Поиск приложений"
            item.searchField.sendsSearchStringImmediately = true
            item.searchField.delegate = self
            item.searchField.widthAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
            item.searchField.setContentHuggingPriority(.required, for: .horizontal)
            navigation.$search.sink { [weak field = item.searchField] value in
                if field?.stringValue != value { field?.stringValue = value }
            }.store(in: &toolbarSubscriptions)
            return item
        }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.isBordered = false
        switch identifier.rawValue {
        case "Systra.Brand":
            item.label = "Systra"
            item.visibilityPriority = .low
            item.view = NSHostingView(rootView: WindowBrand(monitor: monitor, navigation: navigation))
        case "Systra.Tabs":
            item.label = "Разделы Systra"
            item.visibilityPriority = .high
            item.view = ToolbarHostingView(rootView: WindowTabs(navigation: navigation))
        default: return nil
        }
        return item
    }
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else { return }
        navigation.search = field.stringValue
        if !navigation.search.isEmpty && ![MainTab.apps, .cpu, .memory].contains(navigation.tab) { navigation.tab = .apps }
    }
    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = status.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        NSApp.setActivationPolicy(.accessory)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc func show() {
        popover.performClose(nil)
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
}
@main struct SystraMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
