import AppKit
import ApplicationServices

@MainActor
final class NativeWorkspace: NSObject, AppWorkspace {
    private var selectedApps: [SelectedApp] = []
    private var runningApps: [pid_t: NativeRunningApp] = [:]
    private var observingWorkspace = false

    var accessibilityGranted: Bool { AXIsProcessTrustedWithOptions(nil) }

    func requestAccessibilityAccess() {
        // The SDK imports this constant as mutable global state, which Swift 6 rejects.
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func trackApplications(_ apps: [SelectedApp]) {
        selectedApps = apps
        let center = NSWorkspace.shared.notificationCenter
        if apps.isEmpty {
            center.removeObserver(self)
            observingWorkspace = false
        } else if !observingWorkspace {
            for notification in [NSWorkspace.didLaunchApplicationNotification,
                                 NSWorkspace.didActivateApplicationNotification,
                                 NSWorkspace.didTerminateApplicationNotification] {
                center.addObserver(self, selector: #selector(applicationsChanged), name: notification, object: nil)
            }
            observingWorkspace = true
        }
        refreshApplications()
    }

    @objc private func applicationsChanged(_ notification: Notification) {
        refreshApplications()
    }

    private func refreshApplications() {
        for (pid, running) in runningApps {
            guard !running.application.isTerminated,
                  selectedApps.contains(where: { matches(running.application, selected: $0) }) else {
                running.stopTracking()
                runningApps.removeValue(forKey: pid)
                continue
            }
        }
        for app in selectedApps {
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
                where matches(running, selected: app) {
                tracker(for: running).observeCurrentFocus()
            }
        }
    }

    private func matches(_ running: NSRunningApplication, selected app: SelectedApp) -> Bool {
        !running.isTerminated && running.bundleIdentifier == app.bundleIdentifier
            && running.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == app.url
    }

    private func tracker(for application: NSRunningApplication) -> NativeRunningApp {
        let pid = application.processIdentifier
        if let existing = runningApps[pid], !existing.application.isTerminated { return existing }
        runningApps[pid]?.stopTracking()
        let running = NativeRunningApp(application: application)
        runningApps[pid] = running
        return running
    }

    isolated deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for running in runningApps.values { running.stopTracking() }
    }

    func selectApplication(at url: URL) throws -> SelectedApp {
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedURL.isFileURL, resolvedURL.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: resolvedURL),
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
              let identifier = bundle.bundleIdentifier,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw PeekabooError("Choose an installed .app with a valid executable and bundle identifier.")
        }
        guard identifier != Bundle.main.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool != true else {
            throw PeekabooError("Choose an app with a user interface, rather than Peekaboo or a background-only utility.")
        }
        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ""
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? resolvedURL.deletingPathExtension().lastPathComponent : displayName
        return SelectedApp(bundleIdentifier: identifier, url: resolvedURL, name: name)
    }

    func runningApplication(for app: SelectedApp) throws -> (any RunningApp)? {
        try validateInstalledCopy(app)
        let matches = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).filter {
            !$0.isTerminated && $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == app.url
        }
        guard matches.count <= 1 else {
            throw PeekabooError("Multiple instances of \(app.name) are running from the selected copy. Quit the extra instance and try again.")
        }
        return matches.first.map { tracker(for: $0) }
    }

    func launch(_ app: SelectedApp) async throws {
        try validateInstalledCopy(app)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.allowsRunningApplicationSubstitution = false
        configuration.promptsUserIfNeeded = false
        let application = try await NSWorkspace.shared.openApplication(at: app.url, configuration: configuration)
        tracker(for: application).observeCurrentFocus()
    }

    private func validateInstalledCopy(_ app: SelectedApp) throws {
        do {
            let installed = try selectApplication(at: app.url)
            guard installed.bundleIdentifier == app.bundleIdentifier else {
                throw PeekabooError("The bundle identifier has changed.")
            }
        } catch {
            throw PeekabooError("Cannot use \(app.name) at \(app.url.path). Select the app again. \(error.localizedDescription)")
        }
    }
}

@MainActor
private final class NativeRunningApp: RunningApp {
    let application: NSRunningApplication
    private let windowTracker: AccessibilityWindows

    init(application: NSRunningApplication) {
        self.application = application
        windowTracker = AccessibilityWindows(application: application)
        windowTracker.observeCurrentFocus()
    }

    func windows() throws -> [AppWindow] { try windowTracker.windows() }

    func restoreWindow(_ id: UUID) throws { try windowTracker.restoreWindow(id) }

    func observeCurrentFocus() { windowTracker.observeCurrentFocus() }

    func stopTracking() { windowTracker.stop() }

    var isActive: Bool { application.isActive }

    func hide() async -> Bool {
        if application.hide() { return true }
        // macOS 26.6.2 can return false while hiding succeeds on a later run-loop turn.
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !application.isHidden && !application.isTerminated && ContinuousClock.now < deadline {
            do { try await Task.sleep(for: .milliseconds(20)) }
            catch { return false }
        }
        return application.isHidden
    }

    func activate(options: NSApplication.ActivationOptions) -> Bool {
        application.activate(options: options)
    }
}
