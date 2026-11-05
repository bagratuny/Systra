import AppKit
import Combine
import ServiceManagement

enum LoginItemState { case disabled, enabled, requiresApproval, unavailable }

@MainActor protocol LoginItemService {
    var state: LoginItemState { get }
    func register() throws
    func unregister() throws
}
@MainActor private struct SystemLoginItemService: LoginItemService {
    var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

@MainActor final class LoginItemSettings: ObservableObject {
    static let shared = LoginItemSettings(service: SystemLoginItemService())
    @Published private(set) var state: LoginItemState
    @Published private(set) var error: String?
    private let service: any LoginItemService
    var isRequested: Bool { state == .enabled || state == .requiresApproval }
    init(service: any LoginItemService) {
        self.service = service
        state = service.state
    }
    func refresh() { state = service.state }
    func setEnabled(_ enabled: Bool) {
        error = nil
        refresh()
        guard enabled != isRequested else { return }
        do {
            if enabled { try service.register() }
            else { try service.unregister() }
        } catch {
            // macOS can register a request but still require approval in Login Items.
            if service.state != .requiresApproval {
                self.error = L("Не удалось изменить автозапуск: {0}", error.localizedDescription)
            }
        }
        refresh()
    }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
