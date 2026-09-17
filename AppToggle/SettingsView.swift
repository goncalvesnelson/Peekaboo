import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var flow: AssignmentFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AppToggle").font(.title2.bold())
            Text("Give an app a shortcut to bring it forward or hide it. Closed apps launch when you use their shortcut.")
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(flow.assignments) { assignment in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                appLabel(assignment.app)
                                Spacer()
                                Text(assignment.shortcut.label).font(.system(.body, design: .rounded).monospaced())
                            }
                            HStack {
                                Button("Change Shortcut…") { flow.beginRecording(for: assignment.id) }
                                Button("Choose App…") { chooseApplication(replacing: assignment.id) }
                                Button("Delete Shortcut", role: .destructive) { flow.deleteAssignment(assignment.id) }
                            }
                            .disabled(flow.isRecording)
                            if let message = flow.registrationErrors[assignment.id] {
                                Text(message).foregroundStyle(.red).font(.callout)
                            }
                        }
                        Divider()
                    }
                    if let app = flow.selectedApp, flow.recordingAssignmentID == nil {
                        HStack {
                            appLabel(app)
                            Spacer()
                            Button("Record Shortcut…") { flow.beginRecording() }
                                .disabled(flow.isRecording)
                        }
                    }
                    Button("Choose App…") { chooseApplication() }
                        .disabled(flow.isRecording)
                }
            }
            .frame(minHeight: 130, maxHeight: 330)

            if flow.isRecording {
                HStack {
                    Text("Press a shortcut, then release its key. Escape cancels.")
                    Spacer()
                    Button("Cancel") { flow.cancelRecording() }
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            if let message = flow.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message).foregroundStyle(.red).textSelection(.enabled)
                    HStack {
                        Button("Dismiss") { flow.errorMessage = nil }
                        Button("Reload Saved Assignments") { flow.load() }
                            .disabled(flow.isRecording)
                    }
                }
            }

            Text("Use Command, Control, or Option with a key. Labels reflect the keyboard layout used when recording. Windows keep their minimized state and Spaces.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 560)
        .background(ShortcutRecorder(flow: flow).frame(width: 0, height: 0))
        .onAppear { NSApplication.shared.activate() }
        .onDisappear { flow.cancelRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            flow.cancelRecording()
        }
    }

    private func appLabel(_ app: SelectedApp) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading) {
                Text(app.name).font(.headline)
                Text(app.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private func chooseApplication(replacing id: UUID? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Choose an app for AppToggle"
        panel.prompt = "Choose App"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard flow.selectApplication(at: url, replacing: id) else { return }
        if let id { flow.beginRecording(for: id) }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let flow: AssignmentFlow

    func makeCoordinator() -> Coordinator { Coordinator(flow: flow) }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.setRecording(flow.isRecording)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.setRecording(false)
    }

    @MainActor
    final class Coordinator {
        private let flow: AssignmentFlow
        private var monitor: Any?

        init(flow: AssignmentFlow) { self.flow = flow }

        func setRecording(_ recording: Bool) {
            if !recording {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
                return
            }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self, self.flow.isRecording else { return event }
                self.flow.record(event)
                return nil
            }
        }
    }
}
