import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginService: ObservableObject {
    enum Status {
        case enabled
        case disabled
        case requiresApproval
        case unavailable
    }

    static let shared = LaunchAtLoginService()

    @Published private(set) var status: Status = .disabled

    private static let migrationVersionKey = "launchAtLoginMigrationVersion"
    private static let currentMigrationVersion = 3

    private init() {
        refresh()
    }

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    func setEnabled(_ isEnabled: Bool) {
        if #available(macOS 13.0, *) {
            setModernLoginItemEnabled(isEnabled)
            if !isEnabled {
                _ = setLegacyLoginItemEnabled(false)
            }
        } else {
            setLegacyLoginItemEnabled(isEnabled)
        }
        refresh()
    }

    func refresh() {
        if #available(macOS 13.0, *) {
            status = modernStatus()
        } else {
            status = isLegacyLoginItemEnabled() ? .enabled : .disabled
        }
    }

    func migrateIfNeeded() {
        guard #available(macOS 13.0, *) else {
            return
        }

        guard UserDefaults.standard.integer(forKey: Self.migrationVersionKey) < Self.currentMigrationVersion else {
            return
        }

        guard isLegacyLoginItemEnabled() else {
            completeMigration()
            return
        }

        setModernLoginItemEnabled(true)

        let mainAppService = SMAppService.mainApp
        guard mainAppService.status == .enabled else {
            refresh()
            return
        }

        if setLegacyLoginItemEnabled(false) {
            completeMigration()
        }
    }

    @available(macOS 13.0, *)
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @available(macOS 13.0, *)
    private func modernStatus() -> Status {
        let mainStatus = SMAppService.mainApp.status

        if mainStatus == .requiresApproval {
            return .requiresApproval
        }
        if mainStatus == .enabled || isLegacyLoginItemEnabled() {
            return .enabled
        }
        if mainStatus == .notFound {
            return .unavailable
        }
        return .disabled
    }

    @available(macOS 13.0, *)
    private func setModernLoginItemEnabled(_ isEnabled: Bool) {
        let mainAppService = SMAppService.mainApp
        let isRegistered = mainAppService.status == .enabled || mainAppService.status == .requiresApproval
        guard isRegistered != isEnabled else { return }

        do {
            if isEnabled {
                try mainAppService.register()
            } else {
                try mainAppService.unregister()
            }
        } catch {
            print("Failed to \(isEnabled ? "enable" : "disable") launch at login [modern]:", error.localizedDescription)
        }
    }

    private func isLegacyLoginItemEnabled() -> Bool {
        guard let jobs = SMCopyAllJobDictionaries(kSMDomainUserLaunchd),
              let allJobs = jobs.takeRetainedValue() as? [[String: AnyObject]] else {
            return false
        }

        let launcherJob = allJobs.first {
            $0["Label"] as? String == AppConstants.launcherBundleId
        }
        return launcherJob?["OnDemand"] as? Bool ?? false
    }

    @discardableResult
    private func setLegacyLoginItemEnabled(_ isEnabled: Bool) -> Bool {
        let succeeded = SMLoginItemSetEnabled(AppConstants.launcherBundleId as CFString, isEnabled)
        if !succeeded {
            print("Failed to \(isEnabled ? "enable" : "disable") launch at login [legacy]")
        }
        return succeeded
    }

    private func completeMigration() {
        UserDefaults.standard.set(Self.currentMigrationVersion, forKey: Self.migrationVersionKey)
        refresh()
    }
}
