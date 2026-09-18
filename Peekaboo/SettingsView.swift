import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var flow: AssignmentFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("App shortcuts").font(.title2.weight(.semibold))
                Text("Click a shortcut, then press the new keys.")
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 0) {
                    if flow.assignments.isEmpty && flow.selectedApp == nil {
                        VStack(spacing: 10) {
                            Image(systemName: "keyboard").font(.system(size: 30)).foregroundStyle(.tertiary)
                            Text("Add your first app").font(.headline)
                            Text("Give an app a shortcut to bring it forward or hide it.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 38)
                    }

                    ForEach(flow.assignments) { assignment in
                        if assignment.id != flow.assignments.first?.id {
                            Divider().padding(.leading, 54)
                        }
                        assignmentRow(assignment)
                    }

                    if let app = flow.selectedApp, flow.replacingID == nil {
                        if !flow.assignments.isEmpty { Divider().padding(.leading, 54) }
                        HStack(spacing: 14) {
                            appLabel(app)
                            Spacer(minLength: 16)
                            shortcutField(app: app, assignmentID: nil, shortcut: nil)
                            Color.clear.frame(width: 26, height: 26)
                        }
                        .padding(14)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                }
                .padding(1)
            }
            .frame(minHeight: 180, maxHeight: 340)

            HStack {
                Button { chooseApplication() } label: {
                    Label("Add App…", systemImage: "plus")
                }
                .disabled(flow.isRecording)
                Spacer()
                Text(flow.isRecording ? "Release the key to save. Escape cancels." : "Changes save automatically.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            if !flow.accessibilityGranted {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Allow Accessibility to restore minimized windows", systemImage: "macwindow")
                        .font(.callout.weight(.medium))
                    Text("Peekaboo uses window focus to restore only your most recently used minimized window. Enable Peekaboo in System Settings → Privacy & Security → Accessibility.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Allow Accessibility…") { flow.requestAccessibilityAccess() }
                        .disabled(flow.isRecording)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            if let message = flow.errorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).textSelection(.enabled)
                    HStack {
                        Button("Dismiss") { flow.errorMessage = nil }
                        Button("Reload Saved Assignments") { flow.load() }
                            .disabled(flow.isRecording)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }

            Text("Include Command, Control, or Option. Your shortcut launches a closed app, brings it forward, or hides it.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(ShortcutRecorder(flow: flow).frame(width: 0, height: 0))
        .onAppear {
            NSApplication.shared.activate()
            flow.refreshAccessibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            flow.refreshAccessibility()
        }
        .onDisappear { flow.cancelRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            flow.cancelRecording()
        }
    }

    private func assignmentRow(_ assignment: Assignment) -> some View {
        let app = flow.replacingID == assignment.id ? flow.selectedApp ?? assignment.app : assignment.app
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Button { chooseApplication(replacing: assignment.id) } label: { appLabel(assignment.app) }
                    .buttonStyle(.plain)
                    .disabled(flow.isRecording)
                    .help("Choose a different app")
                    .accessibilityLabel("Change app for \(assignment.app.name)")
                Spacer(minLength: 16)
                shortcutField(app: app, assignmentID: assignment.id, shortcut: assignment.shortcut)
                Button(role: .destructive) { flow.deleteAssignment(assignment.id) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(flow.isRecording)
                .help("Delete shortcut for \(assignment.app.name)")
                .accessibilityLabel("Delete shortcut for \(assignment.app.name)")
            }
            if app != assignment.app {
                Text("Pending app: \(app.name) (\(app.url.path)). Record a shortcut to save.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.leading, 40)
            }
            if let message = flow.registrationErrors[assignment.id] {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
                    .padding(.leading, 40)
            }
            if let message = flow.triggerErrors[assignment.id] {
                VStack(alignment: .leading, spacing: 6) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).textSelection(.enabled)
                    Button("Dismiss") { flow.triggerErrors[assignment.id] = nil }
                        .accessibilityLabel("Dismiss toggle error for \(assignment.app.name)")
                }
                .font(.callout)
                .padding(.leading, 40)
            }
        }
        .padding(14)
    }

    private func shortcutField(app: SelectedApp, assignmentID: UUID?, shortcut: Shortcut?) -> some View {
        let recording = flow.isRecording && flow.recordingAssignmentID == assignmentID
        return HStack(spacing: 0) {
            Button { flow.beginRecording(for: assignmentID) } label: {
                Text(recording ? "Type shortcut…" : shortcut?.label ?? "Record shortcut")
                    .font(.system(size: 13, weight: shortcut == nil || recording ? .regular : .medium))
                    .foregroundStyle(recording ? Color.accentColor : shortcut == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(flow.isRecording && !recording)
            .accessibilityLabel("Shortcut for \(app.name)")
            .accessibilityValue(recording ? "Recording" : shortcut?.label ?? "Not set")
            .help("Click to record a shortcut")

            if recording {
                Button { flow.cancelRecording() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .accessibilityLabel("Cancel recording")
                .help("Cancel recording")
            }
        }
        .frame(width: 150)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(recording ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.6),
                              lineWidth: recording ? 2 : 0.5)
        }
    }

    private func appLabel(_ app: SelectedApp) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                Text(app.url.path).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .help(app.url.path)
    }

    private func chooseApplication(replacing id: UUID? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Choose an app for Peekaboo"
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
