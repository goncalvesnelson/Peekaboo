import AppKit
import Carbon
import Observation

@MainActor
@Observable
final class AssignmentFlow {
    private(set) var assignments: [Assignment] = [] {
        didSet { workspace.trackApplications(assignments.map(\.app)) }
    }
    private(set) var accessibilityGranted = false
    private(set) var selectedApp: SelectedApp?
    private(set) var isRecording = false
    private(set) var recordingAssignmentID: UUID?
    var errorMessage: String?
    private(set) var registrationErrors: [UUID: String] = [:]

    private let store: AssignmentStore
    private let hotkeys: any HotkeyRegistry
    private let workspace: any AppWorkspace
    private var registrations: [UUID: UUID] = [:]
    private var generations: [UUID: UUID] = [:]
    private var pendingCleanup = Set<UUID>()
    private var inFlight = Set<UUID>()
    private var pendingShortcut: Shortcut?
    private(set) var replacingID: UUID?
    private var canSave = false

    init(store: AssignmentStore, hotkeys: any HotkeyRegistry, workspace: any AppWorkspace) {
        self.store = store
        self.hotkeys = hotkeys
        self.workspace = workspace
    }

    func load() {
        guard !isRecording else { return }
        refreshAccessibility()
        do {
            let loaded = try store.load()
            try cleanUpRegistrations()
            for id in Array(registrations.keys) { try unregister(id) }
            assignments = loaded
            canSave = true
            errorMessage = nil
            registrationErrors = [:]
            restoreRegistrations()
        } catch {
            canSave = false
            errorMessage = error.localizedDescription
            restoreRegistrations()
        }
    }

    func refreshAccessibility() {
        accessibilityGranted = workspace.accessibilityGranted
        workspace.trackApplications(assignments.map(\.app))
    }

    func requestAccessibilityAccess() {
        workspace.requestAccessibilityAccess()
        refreshAccessibility()
    }

    func stopTracking() {
        workspace.trackApplications([])
    }

    @discardableResult
    func selectApplication(at url: URL, replacing id: UUID? = nil) -> Bool {
        do {
            selectedApp = try workspace.selectApplication(at: url)
            replacingID = id
            errorMessage = nil
            return true
        } catch {
            selectedApp = nil
            replacingID = nil
            errorMessage = error.localizedDescription
            return false
        }
    }

    func beginRecording(for id: UUID? = nil) {
        guard !isRecording else { return }
        guard canSave else {
            errorMessage = "Reload assignments successfully before making changes. Saved file: \(store.url.path)"
            return
        }
        let targetID = id ?? replacingID
        if let targetID, replacingID != targetID {
            selectedApp = assignments.first(where: { $0.id == targetID })?.app
        }
        guard selectedApp != nil else {
            errorMessage = "Select an application before recording a shortcut."
            return
        }
        replacingID = targetID
        recordingAssignmentID = targetID
        pendingShortcut = nil
        errorMessage = nil
        isRecording = true
        do {
            try cleanUpRegistrations()
            for id in Array(registrations.keys) { try unregister(id) }
        } catch {
            isRecording = false
            recordingAssignmentID = nil
            errorMessage = "Cannot start recording: \(error.localizedDescription)"
            restoreRegistrations()
        }
    }

    func record(_ event: NSEvent) {
        guard isRecording else { return }
        if event.type == .keyDown {
            guard !event.isARepeat else { return }
            if event.keyCode == UInt16(kVK_Escape) {
                cancelRecording()
                return
            }
            do {
                pendingShortcut = try Shortcut(event: event)
                errorMessage = nil
            } catch {
                pendingShortcut = nil
                errorMessage = error.localizedDescription
            }
        } else if event.type == .keyUp, let shortcut = pendingShortcut, shortcut.keyCode == event.keyCode {
            finishRecording(shortcut)
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        pendingShortcut = nil
        recordingAssignmentID = nil
        selectedApp = nil
        replacingID = nil
        restoreRegistrations()
    }

    func deleteAssignment(_ id: UUID) {
        guard !isRecording else { return }
        guard canSave else {
            errorMessage = "Reload assignments successfully before making changes. Saved file: \(store.url.path)"
            return
        }
        guard assignments.contains(where: { $0.id == id }) else { return }
        let updated = assignments.filter { $0.id != id }
        do {
            try store.save(updated)
            assignments = updated
            errorMessage = nil
            do { try unregister(id) }
            catch {
                if let registration = registrations[id] { pendingCleanup.insert(registration) }
                registrations[id] = nil
                generations[id] = nil
                errorMessage = "Assignment removed, but its shortcut could not be released: \(error.localizedDescription). Use Reload Saved Assignments to retry."
            }
            registrationErrors[id] = nil
            if replacingID == id {
                selectedApp = nil
                replacingID = nil
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func trigger(_ id: UUID) async {
        guard !isRecording, !inFlight.contains(id), let assignment = assignments.first(where: { $0.id == id }) else { return }
        inFlight.insert(id)
        defer { inFlight.remove(id) }
        do {
            guard let running = try workspace.runningApplication(for: assignment.app) else {
                try await workspace.launch(assignment.app)
                return
            }
            accessibilityGranted = workspace.accessibilityGranted
            var windowError: Error?
            var windows: [AppWindow]?
            do { windows = try running.windows() }
            catch { windowError = error }
            if running.isActive && (windows == nil || windows?.contains(where: { !$0.isMinimized }) == true) {
                guard await running.hide() else { throw PeekabooError("Could not hide \(assignment.app.name).") }
                if let windowError { throw windowError }
                return
            }
            if let windows {
                do {
                    let minimized = windows.filter(\.isMinimized)
                    let recent = windows.filter { $0.focusOrder != nil }.max {
                        ($0.focusOrder ?? 0) < ($1.focusOrder ?? 0)
                    }
                    if let window = recent ?? (windows.count == 1 ? windows.first : nil) {
                        if window.isMinimized { try running.restoreWindow(window.id) }
                    } else if !minimized.isEmpty {
                        throw PeekabooError("The most recently used window of \(assignment.app.name) is not known yet. Open the window you want once so Peekaboo can track it.")
                    }
                } catch { windowError = error }
            }
            guard running.activate(options: [.activateAllWindows]) else {
                let message = "Could not activate \(assignment.app.name). Try the shortcut again."
                throw PeekabooError([windowError?.localizedDescription, message].compactMap { $0 }.joined(separator: "\n"))
            }
            if let windowError { throw windowError }
        } catch { errorMessage = error.localizedDescription }
    }

    private func finishRecording(_ shortcut: Shortcut) {
        guard let app = selectedApp else { return }
        let id = recordingAssignmentID ?? UUID()
        isRecording = false
        recordingAssignmentID = nil
        pendingShortcut = nil
        restoreRegistrations()
        guard !assignments.contains(where: { $0.id != id && $0.shortcut.matches(shortcut) }) else {
            errorMessage = "This shortcut already belongs to another assignment."
            return
        }
        let candidate = Assignment(id: id, app: app, shortcut: shortcut)
        var updated = assignments
        if let index = updated.firstIndex(where: { $0.id == id }) { updated[index] = candidate }
        else { updated.append(candidate) }
        do {
            if let previous = assignments.first(where: { $0.id == id }), previous.shortcut.matches(shortcut), registrations[id] != nil {
                try store.save(updated)
                assignments = updated
            } else {
                let registration = try register(candidate)
                do { try store.save(updated) }
                catch let saveError {
                    do { try hotkeys.unregister(registration.id) }
                    catch {
                        pendingCleanup.insert(registration.id)
                        throw PeekabooError("\(saveError.localizedDescription) Cannot release the unsaved shortcut: \(error.localizedDescription)")
                    }
                    throw saveError
                }
                if registrations[id] != nil {
                    do { try unregister(id) }
                    catch {
                        if let previousRegistration = registrations[id] { pendingCleanup.insert(previousRegistration) }
                        errorMessage = "Assignment saved, but the previous shortcut could not be released: \(error.localizedDescription)"
                    }
                }
                assignments = updated
                registrations[id] = registration.id
                generations[id] = registration.generation
            }
            registrationErrors[id] = nil
            selectedApp = nil
            replacingID = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func register(_ assignment: Assignment) throws -> (id: UUID, generation: UUID) {
        let generation = UUID()
        let id = try hotkeys.register(assignment.shortcut) { [weak self] in
            guard let self, !self.isRecording, self.generations[assignment.id] == generation,
                  self.assignments.contains(where: { $0.id == assignment.id && $0.shortcut.matches(assignment.shortcut) }) else { return }
            Task {
                guard self.generations[assignment.id] == generation else { return }
                await self.trigger(assignment.id)
            }
        }
        return (id, generation)
    }

    private func unregister(_ id: UUID) throws {
        guard let registration = registrations[id] else { return }
        try hotkeys.unregister(registration)
        registrations[id] = nil
        generations[id] = nil
    }

    private func cleanUpRegistrations() throws {
        for registration in pendingCleanup {
            try hotkeys.unregister(registration)
            pendingCleanup.remove(registration)
        }
    }

    private func restoreRegistrations() {
        for assignment in assignments where registrations[assignment.id] == nil {
            do {
                let registration = try register(assignment)
                registrations[assignment.id] = registration.id
                generations[assignment.id] = registration.generation
                registrationErrors[assignment.id] = nil
            } catch { registrationErrors[assignment.id] = error.localizedDescription }
        }
    }
}
