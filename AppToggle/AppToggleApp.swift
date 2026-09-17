import AppKit
import SwiftUI

@main
struct AppToggleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            SettingsLink { Text("Settings…") }
            if let message = delegate.flow.errorMessage {
                Text(message)
            }
            if !delegate.flow.registrationErrors.isEmpty {
                Text("A shortcut is unavailable. Open Settings to correct it.")
            }
            Divider()
            Button("Quit AppToggle") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Label("AppToggle", systemImage: delegate.flow.errorMessage == nil && delegate.flow.registrationErrors.isEmpty
                  ? "rectangle.on.rectangle" : "exclamationmark.triangle")
        }
        Settings {
            SettingsView(flow: delegate.flow)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotkeys = CarbonHotkeys()
    lazy var flow = AssignmentFlow(store: AssignmentStore(), hotkeys: hotkeys, workspace: NativeWorkspace())

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["APPTOGGLE_TESTING"] != "1" else { return }
        flow.load()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do {
            try hotkeys.shutdown()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Shortcut cleanup failed"
            alert.informativeText = "\(error.localizedDescription) macOS will release this process’s shortcuts when AppToggle quits."
            alert.addButton(withTitle: "Quit")
            alert.runModal()
        }
        return .terminateNow
    }
}
