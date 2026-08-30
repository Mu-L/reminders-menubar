import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: AppConstants.mainBundleId).isEmpty else {
            // main app is already running
            NSApp.terminate(self)
            return
        }
        
        guard let appUrl = containingMainAppURL() else {
            // The launcher must be embedded in the main app bundle.
            NSApp.terminate(self)
            return
        }
        
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(
            at: appUrl,
            configuration: configuration,
            completionHandler: { _, _ in
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
        )
    }

    private func containingMainAppURL() -> URL? {
        let mainAppURL = URL(
            fileURLWithPath: "../../../..",
            isDirectory: true,
            relativeTo: Bundle.main.bundleURL
        ).standardizedFileURL
        guard Bundle(url: mainAppURL)?.bundleIdentifier == AppConstants.mainBundleId else {
            return nil
        }
        return mainAppURL
    }
}
