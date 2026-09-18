import AppKit
import SwiftUI

@main
struct PeekabooApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            SettingsButton()
            if let message = delegate.flow.errorMessage {
                Text(message)
            }
            ForEach(delegate.flow.assignments) { assignment in
                if let message = delegate.flow.triggerErrors[assignment.id] {
                    Text("\(assignment.app.name): \(message)")
                }
            }
            if !delegate.flow.accessibilityGranted {
                Text("Allow Accessibility in Settings to restore minimized windows.")
            }
            if !delegate.flow.registrationErrors.isEmpty {
                Text("A shortcut is unavailable. Open Settings to correct it.")
            }
            Divider()
            Button("Quit Peekaboo") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Label {
                Text("Peekaboo")
            } icon: {
                if !delegate.flow.hasWarnings {
                    Image("MenuBarIcon").renderingMode(.template)
                } else {
                    Image(systemName: "exclamationmark.triangle")
                }
            }
        }
        Settings {
            SettingsView(flow: delegate.flow)
        }
    }
}

struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            openSettings()
            // A Settings click explicitly requests focus even while another app is active.
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotkeys = CarbonHotkeys()
    lazy var flow = AssignmentFlow(store: AssignmentStore(), hotkeys: hotkeys, workspace: NativeWorkspace())

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["PEEKABOO_TESTING"] != "1" else { return }
        flow.load()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        flow.stopTracking()
        do {
            try hotkeys.shutdown()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Shortcut cleanup failed"
            alert.informativeText = "\(error.localizedDescription) macOS will release this process’s shortcuts when Peekaboo quits."
            alert.addButton(withTitle: "Quit")
            alert.runModal()
        }
        return .terminateNow
    }
}
