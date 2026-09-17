import AppKit

@MainActor
struct NativeWorkspace: AppWorkspace {
    func selectApplication(at url: URL) throws -> SelectedApp {
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedURL.isFileURL, resolvedURL.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: resolvedURL),
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
              let identifier = bundle.bundleIdentifier,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw AppToggleError("Choose an installed .app with a valid executable and bundle identifier.")
        }
        guard identifier != Bundle.main.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool != true else {
            throw AppToggleError("Choose an app with a user interface, rather than AppToggle or a background-only utility.")
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
            throw AppToggleError("Multiple instances of \(app.name) are running from the selected copy. Quit the extra instance and try again.")
        }
        return matches.first.map { NativeRunningApp(application: $0) }
    }

    func launch(_ app: SelectedApp) async throws {
        try validateInstalledCopy(app)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.allowsRunningApplicationSubstitution = false
        configuration.promptsUserIfNeeded = false
        _ = try await NSWorkspace.shared.openApplication(at: app.url, configuration: configuration)
    }

    private func validateInstalledCopy(_ app: SelectedApp) throws {
        do {
            let installed = try selectApplication(at: app.url)
            guard installed.bundleIdentifier == app.bundleIdentifier else {
                throw AppToggleError("The bundle identifier has changed.")
            }
        } catch {
            throw AppToggleError("Cannot use \(app.name) at \(app.url.path). Select the app again. \(error.localizedDescription)")
        }
    }
}

@MainActor
private final class NativeRunningApp: RunningApp {
    private let application: NSRunningApplication

    init(application: NSRunningApplication) { self.application = application }

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
