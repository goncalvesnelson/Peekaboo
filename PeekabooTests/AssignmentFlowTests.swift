import AppKit
import Carbon
import Testing
@testable import Peekaboo

@MainActor
struct AssignmentFlowTests {
    @Test func assignmentSurvivesRestartAndTogglesFromCurrentAppState() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let assignment = try #require(flow.assignments.first)
        #expect(assignment.app == fixture.app)
        #expect(assignment.shortcut.label.hasPrefix("⌃⌥"))
        #expect(!assignment.shortcut.keyLabel.isEmpty)
        #expect(!flow.isRecording)
        #expect(flow.errorMessage == nil)

        let restarted = fixture.flow(hotkeys: FakeHotkeys())
        restarted.load()
        #expect(restarted.assignments == [assignment])
        let running = FakeRunningApp()
        fixture.workspace.running[fixture.app.url] = running
        await restarted.trigger(assignment.id)
        #expect(running.isActive)
        #expect(running.activationOptions == [.activateAllWindows])
        await restarted.trigger(assignment.id)
        #expect(running.isHidden)
        running.isActive = false
        running.isHidden = false
        await restarted.trigger(assignment.id)
        #expect(running.isActive)
        running.isActive = false
        running.isHidden = true
        await restarted.trigger(assignment.id)
        #expect(!running.isHidden)
        #expect(running.isActive)

        let older = AppWindow(id: UUID(), isMinimized: true, focusOrder: 1)
        let recent = AppWindow(id: UUID(), isMinimized: true, focusOrder: 2)
        running.appWindows = [recent, older]
        await restarted.trigger(assignment.id)
        #expect(running.isActive)
        #expect(!running.isHidden)
        #expect(running.appWindows.first(where: { $0.id == recent.id })?.isMinimized == false)
        #expect(running.appWindows.first(where: { $0.id == older.id })?.isMinimized == true)
        await restarted.trigger(assignment.id)
        #expect(running.isHidden)
        await restarted.trigger(assignment.id)
        #expect(running.isActive)
        #expect(running.appWindows.first(where: { $0.id == older.id })?.isMinimized == true)
    }

    @Test func unknownWindowHistoryDoesNotGuessAndRecoversAfterFocusIsObserved() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let assignment = try #require(flow.assignments.first)
        let running = FakeRunningApp()
        fixture.workspace.running[fixture.app.url] = running
        let first = AppWindow(id: UUID(), isMinimized: true, focusOrder: nil)
        let second = AppWindow(id: UUID(), isMinimized: true, focusOrder: nil)
        running.appWindows = [first, second]
        await flow.trigger(assignment.id)
        #expect(flow.errorMessage?.contains("Open the window you want once") == true)
        #expect(running.appWindows == [first, second])
        #expect(running.isActive)

        running.isActive = false
        let visible = AppWindow(id: first.id, isMinimized: false, focusOrder: nil)
        running.appWindows = [visible, second]
        await flow.trigger(assignment.id)
        #expect(flow.errorMessage?.contains("Open the window you want once") == true)
        #expect(running.appWindows == [visible, second])

        running.appWindows = [first, AppWindow(id: second.id, isMinimized: true, focusOrder: 1)]
        flow.errorMessage = nil
        await flow.trigger(assignment.id)
        #expect(running.appWindows.first == first)
        #expect(running.appWindows.last?.isMinimized == false)
        #expect(flow.errorMessage == nil)
        #expect(flow.assignments == [assignment])
    }

    @Test func singleMinimizedWindowRestoresWithoutHistoryAndClosedWindowHistoryIsNotUsed() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let assignment = try #require(flow.assignments.first)
        let running = FakeRunningApp()
        running.appWindows = [AppWindow(id: UUID(), isMinimized: true, focusOrder: nil)]
        fixture.workspace.running[fixture.app.url] = running
        await flow.trigger(assignment.id)
        #expect(running.appWindows.first?.isMinimized == false)
        #expect(running.isActive)
        running.appWindows = [AppWindow(id: UUID(), isMinimized: true, focusOrder: nil)]
        await flow.trigger(assignment.id)
        #expect(running.appWindows.first?.isMinimized == false)
        #expect(flow.errorMessage == nil)
    }

    @Test func windowAccessAndRestorationFailuresPreserveAssignmentsAndAllowOtherApps() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let assignment = try #require(flow.assignments.first)
        let running = FakeRunningApp()
        fixture.workspace.running[fixture.app.url] = running
        fixture.workspace.accessibilityGranted = false
        running.windowError = PeekabooError("Allow Accessibility in Settings.")
        running.isHidden = true
        await flow.trigger(assignment.id)
        #expect(!flow.accessibilityGranted)
        #expect(flow.errorMessage == "Allow Accessibility in Settings.")
        #expect(!running.isHidden)
        #expect(running.isActive)
        await flow.trigger(assignment.id)
        #expect(running.isHidden)
        #expect(!running.isActive)
        #expect(flow.errorMessage == "Allow Accessibility in Settings.")
        flow.requestAccessibilityAccess()
        #expect(fixture.workspace.accessibilityRequested)
        fixture.workspace.accessibilityGranted = true
        flow.refreshAccessibility()
        #expect(flow.accessibilityGranted)
        #expect(fixture.workspace.trackedApps == [fixture.app])

        running.windowError = nil
        running.restoreError = PeekabooError("The window no longer exists.")
        let minimized = AppWindow(id: UUID(), isMinimized: true, focusOrder: 1)
        running.appWindows = [minimized]
        await flow.trigger(assignment.id)
        #expect(flow.errorMessage == "The window no longer exists.")
        #expect(running.appWindows == [minimized])
        #expect(flow.assignments == [assignment])

        let other = SelectedApp(bundleIdentifier: "test.other", url: URL(fileURLWithPath: "/Applications/Other.app"), name: "Other")
        fixture.workspace.selections[other.url] = other
        flow.selectApplication(at: other.url)
        flow.beginRecording()
        try fixture.record(flow, keyCode: 1, characters: "s")
        let second = try #require(flow.assignments.last)
        await flow.trigger(second.id)
        #expect(fixture.workspace.running[other.url]?.isActive == true)
        flow.deleteAssignment(assignment.id)
        #expect(fixture.workspace.trackedApps == [other])
        flow.stopTracking()
        #expect(fixture.workspace.trackedApps.isEmpty)
    }

    @Test func recordingSuspendsShortcutsAndEscapeRestoresSavedAssignment() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let saved = try #require(flow.assignments.first)
        let stale = try #require(fixture.hotkeys.registrations.values.first).action
        flow.beginRecording(for: saved.id)
        #expect(fixture.hotkeys.registrations.isEmpty)
        flow.deleteAssignment(saved.id)
        #expect(flow.assignments == [saved])
        #expect(flow.isRecording)
        stale()
        await Task.yield()
        #expect(fixture.workspace.launched.isEmpty)
        flow.record(try fixture.event(.keyDown, keyCode: UInt16(kVK_Escape), characters: "\u{1b}", flags: []))
        #expect(!flow.isRecording)
        #expect(flow.assignments == [saved])
        #expect(fixture.hotkeys.registrations.count == 1)
        stale()
        await Task.yield()
        #expect(fixture.workspace.launched.isEmpty)
        try #require(fixture.hotkeys.registrations.values.first).action()
        await fixture.workspace.waitForLaunch()
        #expect(fixture.workspace.launched == [fixture.app])
    }

    @Test func recorderRejectsTypingAndIgnoresRepeatUntilMatchingRelease() throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow, flags: [.shift])
        #expect(flow.isRecording)
        #expect(flow.errorMessage != nil)
        flow.record(try fixture.event(.keyDown, isRepeat: true))
        flow.record(try fixture.event(.keyUp))
        #expect(flow.assignments.isEmpty)
        flow.record(try fixture.event(.keyDown, keyCode: UInt16(kVK_Space), characters: " ", flags: [.control, .option, .capsLock, .numericPad]))
        flow.record(try fixture.event(.keyUp, keyCode: 1))
        #expect(flow.isRecording)
        flow.record(try fixture.event(.keyUp, keyCode: UInt16(kVK_Space), characters: " "))
        #expect(flow.assignments.first?.shortcut.modifiers == UInt32(controlKey | optionKey))
        #expect(flow.assignments.first?.shortcut.label == "⌃⌥Space")
    }

    @Test func duplicateAndUnavailableReplacementKeepOriginalAssignmentWorking() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let original = try #require(flow.assignments.first)
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow, keyCode: 1, characters: "s")
        let second = try #require(flow.assignments.last)
        flow.beginRecording(for: original.id)
        try fixture.record(flow, keyCode: 1, characters: "s")
        #expect(flow.assignments == [original, second])
        #expect(flow.errorMessage?.contains("already belongs") == true)
        fixture.hotkeys.rejectedKeys = [2]
        flow.beginRecording(for: original.id)
        try fixture.record(flow, keyCode: 2, characters: "d")
        #expect(flow.assignments == [original, second])
        #expect(flow.errorMessage == "Shortcut unavailable")
        let working = try #require(fixture.hotkeys.registrations.values.first(where: { $0.shortcut.keyCode == 0 }))
        working.action()
        await fixture.workspace.waitForLaunch()
        #expect(fixture.workspace.launched == [fixture.app])

        fixture.hotkeys.rejectedKeys = []
        flow.beginRecording()
        try fixture.record(flow, keyCode: 2, characters: "d")
        #expect(flow.assignments.count == 2)
        #expect(flow.assignments.first?.id == original.id)
        #expect(flow.assignments.first?.shortcut.keyCode == 2)
        #expect(flow.assignments.last == second)
    }

    @Test func appReplacementUsesSelectedCopyAndKeepsSameShortcut() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let original = try #require(flow.assignments.first)
        let copy = SelectedApp(bundleIdentifier: fixture.app.bundleIdentifier,
                               url: URL(fileURLWithPath: "/Other/Editor.app"), name: "Other editor")
        fixture.workspace.selections[copy.url] = copy
        #expect(flow.selectApplication(at: copy.url, replacing: original.id))
        flow.beginRecording(for: original.id)
        try fixture.record(flow)
        let replacement = try #require(flow.assignments.first)
        #expect(replacement.id == original.id)
        #expect(replacement.app == copy)
        #expect(replacement.shortcut == original.shortcut)
        try #require(fixture.hotkeys.registrations.values.first).action()
        await fixture.workspace.waitForLaunch()
        #expect(fixture.workspace.launched == [copy])
        let restarted = fixture.flow(hotkeys: FakeHotkeys())
        restarted.load()
        #expect(restarted.assignments == [replacement])
    }

    @Test func failedSavePreservesAssignmentAndWorkingShortcut() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let original = try #require(flow.assignments.first)
        let backup = fixture.directory.appending(path: "backup.json")
        try FileManager.default.moveItem(at: fixture.store.url, to: backup)
        try FileManager.default.createDirectory(at: fixture.store.url, withIntermediateDirectories: false)
        flow.beginRecording(for: original.id)
        try fixture.record(flow, keyCode: 1, characters: "s")
        #expect(flow.assignments == [original])
        #expect(flow.errorMessage?.contains("Cannot save assignments") == true)
        #expect(fixture.hotkeys.registrations.count == 1)
        try #require(fixture.hotkeys.registrations.values.first).action()
        await fixture.workspace.waitForLaunch()
        #expect(fixture.workspace.launched == [fixture.app])
        try FileManager.default.removeItem(at: fixture.store.url)
        try FileManager.default.moveItem(at: backup, to: fixture.store.url)
        let restarted = fixture.flow(hotkeys: FakeHotkeys())
        restarted.load()
        #expect(restarted.assignments == [original])
    }

    @Test func deletingAssignmentReleasesShortcutAndPreservesOtherAssignmentsAfterReload() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let deleted = try #require(flow.assignments.first)
        let other = SelectedApp(bundleIdentifier: "test.other", url: URL(fileURLWithPath: "/Applications/Other.app"), name: "Other")
        fixture.workspace.selections[other.url] = other
        flow.selectApplication(at: other.url)
        flow.beginRecording()
        try fixture.record(flow, keyCode: 1, characters: "s")
        let remaining = try #require(flow.assignments.last)
        let stale = try #require(fixture.hotkeys.registrations.values.first(where: { $0.shortcut.keyCode == 0 })).action

        flow.deleteAssignment(deleted.id)
        #expect(flow.assignments == [remaining])
        #expect(flow.errorMessage == nil)
        #expect(!fixture.hotkeys.registrations.values.contains(where: { $0.shortcut.keyCode == 0 }))
        stale()
        await Task.yield()
        #expect(fixture.workspace.launched.isEmpty)
        try #require(fixture.hotkeys.registrations.values.first).action()
        await fixture.workspace.waitForLaunch()
        #expect(fixture.workspace.launched == [other])
        flow.load()
        #expect(flow.assignments == [remaining])
        #expect(flow.errorMessage == nil)
        let restarted = fixture.flow(hotkeys: FakeHotkeys())
        restarted.load()
        #expect(restarted.assignments == [remaining])
    }

    @Test func failedDeletionSaveKeepsAssignmentAndShortcutWorking() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let saved = try #require(flow.assignments.first)
        let working = try #require(fixture.hotkeys.registrations.values.first).action
        let backup = fixture.directory.appending(path: "backup.json")
        try FileManager.default.moveItem(at: fixture.store.url, to: backup)
        try FileManager.default.createDirectory(at: fixture.store.url, withIntermediateDirectories: false)

        flow.deleteAssignment(saved.id)
        #expect(flow.assignments == [saved])
        #expect(flow.errorMessage?.contains("Cannot save assignments") == true)
        working()
        await fixture.workspace.waitForLaunch()
        #expect(fixture.workspace.launched == [fixture.app])
        try FileManager.default.removeItem(at: fixture.store.url)
        try FileManager.default.moveItem(at: backup, to: fixture.store.url)
        let restarted = fixture.flow(hotkeys: FakeHotkeys())
        restarted.load()
        #expect(restarted.assignments == [saved])
    }

    @Test func deletionCleanupFailureDisablesCallbackAndReloadReleasesShortcut() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let deleted = try #require(flow.assignments.first)
        fixture.hotkeys.rejectedKeys = [1]
        flow.beginRecording(for: deleted.id)
        try fixture.record(flow, keyCode: 1, characters: "s")
        #expect(flow.selectedApp == fixture.app)
        let stale = try #require(fixture.hotkeys.registrations.values.first).action
        fixture.hotkeys.rejectUnregister = true

        flow.deleteAssignment(deleted.id)
        #expect(flow.assignments.isEmpty)
        #expect(flow.selectedApp == nil)
        #expect(flow.registrationErrors.isEmpty)
        #expect(flow.errorMessage?.contains("Assignment removed") == true)
        #expect(flow.errorMessage?.contains("Reload Saved Assignments") == true)
        stale()
        await Task.yield()
        #expect(fixture.workspace.launched.isEmpty)
        let restarted = fixture.flow(hotkeys: FakeHotkeys())
        restarted.load()
        #expect(restarted.assignments.isEmpty)
        #expect(restarted.errorMessage == nil)

        fixture.hotkeys.rejectUnregister = false
        flow.load()
        #expect(flow.errorMessage == nil)
        #expect(fixture.hotkeys.registrations.isEmpty)
        flow.beginRecording()
        #expect(!flow.isRecording)
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        #expect(flow.assignments.count == 1)
        #expect(flow.assignments.first?.id != deleted.id)
        #expect(flow.errorMessage == nil)
        try #require(fixture.hotkeys.registrations.values.first).action()
        await fixture.workspace.waitForLaunch()
        #expect(fixture.workspace.launched == [fixture.app])
    }

    @Test func unreadableStoreBlocksChangesUntilSuccessfulReload() throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let saved = try #require(flow.assignments.first)
        let malformed = Data("this is not JSON".utf8)
        try malformed.write(to: fixture.store.url)
        flow.load()
        #expect(flow.errorMessage?.contains(fixture.store.url.path) == true)
        flow.deleteAssignment(saved.id)
        #expect(flow.assignments == [saved])
        #expect(flow.errorMessage?.contains("Reload assignments successfully") == true)
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        #expect(!flow.isRecording)
        #expect(try Data(contentsOf: fixture.store.url) == malformed)
        try FileManager.default.removeItem(at: fixture.store.url)
        flow.load()
        flow.beginRecording()
        try fixture.record(flow)
        #expect(flow.assignments.count == 1)
        #expect(flow.errorMessage == nil)
    }

    @Test func savedInvalidValuesAreRejectedWithoutChangingFile() throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let valid = Assignment(id: UUID(), app: fixture.app,
                               shortcut: Shortcut(keyCode: 0, modifiers: UInt32(controlKey), keyLabel: "A"))
        let remoteURL = try #require(URL(string: "https://example.com/Editor.app"))
        let invalidApp = SelectedApp(bundleIdentifier: "", url: remoteURL, name: "Editor")
        let invalidShortcut = Shortcut(keyCode: 0, modifiers: 0, keyLabel: "A")
        let cases = [
            [valid, valid],
            [valid, Assignment(id: UUID(), app: fixture.app, shortcut: valid.shortcut)],
            [Assignment(id: UUID(), app: invalidApp, shortcut: valid.shortcut)],
            [Assignment(id: UUID(), app: fixture.app, shortcut: invalidShortcut)]
        ]
        for assignments in cases {
            let data = try JSONEncoder().encode(assignments)
            try data.write(to: fixture.store.url)
            let flow = fixture.flow(hotkeys: FakeHotkeys())
            flow.load()
            #expect(flow.assignments.isEmpty)
            #expect(flow.errorMessage?.contains("Cannot read assignments") == true)
            flow.selectApplication(at: fixture.app.url)
            flow.beginRecording()
            #expect(!flow.isRecording)
            #expect(try Data(contentsOf: fixture.store.url) == data)
        }
    }

    @Test func startupConflictLeavesOtherAssignmentsWorkingAndCanBeCorrected() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow, keyCode: 1, characters: "s")
        let saved = flow.assignments
        let startupHotkeys = FakeHotkeys()
        startupHotkeys.rejectedKeys = [0]
        let restarted = fixture.flow(hotkeys: startupHotkeys)
        restarted.load()
        let unavailable = try #require(saved.first)
        #expect(restarted.assignments == saved)
        #expect(restarted.registrationErrors[unavailable.id] == "Shortcut unavailable")
        try #require(startupHotkeys.registrations.values.first).action()
        await fixture.workspace.waitForLaunch()
        #expect(fixture.workspace.launched == [fixture.app])
        restarted.beginRecording(for: unavailable.id)
        try fixture.record(restarted, keyCode: 2, characters: "d")
        #expect(restarted.registrationErrors.isEmpty)
        #expect(restarted.assignments.first?.shortcut.keyCode == 2)
        #expect(startupHotkeys.registrations.count == 2)
    }

    @Test func suspensionFailureAbortsRecorderAndKeepsShortcutUsable() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let saved = try #require(flow.assignments.first)
        fixture.hotkeys.rejectUnregister = true
        flow.beginRecording(for: saved.id)
        #expect(!flow.isRecording)
        #expect(flow.errorMessage?.contains("Cannot start recording") == true)
        #expect(flow.assignments == [saved])
        try #require(fixture.hotkeys.registrations.values.first).action()
        await fixture.workspace.waitForLaunch()
        #expect(fixture.workspace.launched == [fixture.app])
    }

    @Test func launchingSuppressesRepeatedTriggersUntilCompletionAndRecoversAfterFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let saved = try #require(flow.assignments.first)
        fixture.workspace.holdLaunch = true
        fixture.workspace.launchError = PeekabooError("The selected app was deleted. Select it again.")
        let launching = Task { await flow.trigger(saved.id) }
        await fixture.workspace.waitForLaunch()
        let continuation = try #require(fixture.workspace.launchContinuation)
        await flow.trigger(saved.id)
        #expect(fixture.workspace.launched == [fixture.app])
        continuation.resume()
        await launching.value
        #expect(flow.errorMessage?.contains("Select it again") == true)
        fixture.workspace.holdLaunch = false
        fixture.workspace.launchError = nil
        await flow.trigger(saved.id)
        #expect(fixture.workspace.launched == [fixture.app, fixture.app])
        #expect(fixture.workspace.running[fixture.app.url]?.isActive == true)
    }

    @Test func refusedAppActionsReportErrorsAndOtherAssignmentsKeepWorking() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let first = try #require(flow.assignments.first)
        let other = SelectedApp(bundleIdentifier: "test.other", url: URL(fileURLWithPath: "/Applications/Other.app"), name: "Other")
        fixture.workspace.selections[other.url] = other
        flow.selectApplication(at: other.url)
        flow.beginRecording()
        try fixture.record(flow, keyCode: 1, characters: "s")
        let second = try #require(flow.assignments.last)
        let running = FakeRunningApp()
        fixture.workspace.running[fixture.app.url] = running
        running.isActive = true
        running.refuseHide = true
        await flow.trigger(first.id)
        #expect(flow.errorMessage == "Could not hide Editor.")
        running.isActive = false
        running.isHidden = true
        running.refuseActivation = true
        await flow.trigger(first.id)
        #expect(flow.errorMessage?.contains("Could not activate Editor") == true)
        await flow.trigger(second.id)
        #expect(fixture.workspace.running[other.url]?.isActive == true)
        #expect(flow.assignments == [first, second])
    }

    @Test func failedSelectionCannotReusePreviousDraft() throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        #expect(flow.selectApplication(at: fixture.app.url))
        #expect(!flow.selectApplication(at: URL(fileURLWithPath: "/Applications/Missing.app")))
        #expect(flow.selectedApp == nil)
        flow.beginRecording()
        #expect(!flow.isRecording)
        #expect(flow.assignments.isEmpty)
    }

    @Test func canceledAppReplacementCannotLeakIntoLaterShortcutEdit() throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let original = try #require(flow.assignments.first)
        let other = SelectedApp(bundleIdentifier: "test.other", url: URL(fileURLWithPath: "/Applications/Other.app"), name: "Other")
        fixture.workspace.selections[other.url] = other
        flow.selectApplication(at: other.url, replacing: original.id)
        flow.beginRecording(for: original.id)
        flow.cancelRecording()
        #expect(flow.selectedApp == nil)
        flow.beginRecording(for: original.id)
        try fixture.record(flow, keyCode: 1, characters: "s")
        #expect(flow.assignments.first?.app == fixture.app)
        #expect(flow.assignments.first?.shortcut.keyCode == 1)
    }

    @Test func failedOldShortcutCleanupIsRetriedBeforeRecording() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let original = try #require(flow.assignments.first)
        flow.beginRecording(for: original.id)
        flow.record(try fixture.event(.keyDown, keyCode: 1, characters: "s"))
        fixture.hotkeys.rejectUnregister = true
        flow.record(try fixture.event(.keyUp, keyCode: 1, characters: "s"))
        #expect(flow.assignments.first?.shortcut.keyCode == 1)
        #expect(flow.errorMessage?.contains("previous shortcut could not be released") == true)
        #expect(fixture.hotkeys.registrations.count == 2)
        let stale = try #require(fixture.hotkeys.registrations.values.first(where: { $0.shortcut.keyCode == 0 }))
        stale.action()
        await Task.yield()
        #expect(fixture.workspace.launched.isEmpty)
        flow.beginRecording(for: original.id)
        #expect(!flow.isRecording)
        fixture.hotkeys.rejectUnregister = false
        flow.beginRecording(for: original.id)
        #expect(flow.isRecording)
        #expect(fixture.hotkeys.registrations.isEmpty)
        flow.cancelRecording()
        #expect(fixture.hotkeys.registrations.count == 1)
        #expect(fixture.hotkeys.registrations.values.first?.shortcut.keyCode == 1)
    }

    @Test func failedSaveAndCleanupReportBothErrorsAndRetryCleanup() throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        let original = try #require(flow.assignments.first)
        let backup = fixture.directory.appending(path: "backup.json")
        try FileManager.default.moveItem(at: fixture.store.url, to: backup)
        try FileManager.default.createDirectory(at: fixture.store.url, withIntermediateDirectories: false)
        flow.beginRecording(for: original.id)
        flow.record(try fixture.event(.keyDown, keyCode: 1, characters: "s"))
        fixture.hotkeys.rejectUnregister = true
        flow.record(try fixture.event(.keyUp, keyCode: 1, characters: "s"))
        #expect(flow.errorMessage?.contains("Cannot save assignments") == true)
        #expect(flow.errorMessage?.contains("Cannot release the unsaved shortcut") == true)
        #expect(flow.assignments == [original])
        fixture.hotkeys.rejectUnregister = false
        flow.beginRecording(for: original.id)
        #expect(flow.isRecording)
        #expect(fixture.hotkeys.registrations.isEmpty)
        flow.cancelRecording()
        #expect(fixture.hotkeys.registrations.count == 1)
    }

    @Test func failedReloadRestoresShortcutsAlreadyUnregistered() throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.load()
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow)
        flow.selectApplication(at: fixture.app.url)
        flow.beginRecording()
        try fixture.record(flow, keyCode: 1, characters: "s")
        let saved = flow.assignments
        fixture.hotkeys.failUnregisterAfter = fixture.hotkeys.successfulUnregistrations + 1
        flow.load()
        #expect(flow.assignments == saved)
        #expect(flow.errorMessage?.contains("Cannot unregister shortcut") == true)
        #expect(fixture.hotkeys.registrations.count == 2)
        #expect(Set(fixture.hotkeys.registrations.values.map(\.shortcut.keyCode)) == [0, 1])
        fixture.hotkeys.failUnregisterAfter = nil
        flow.load()
        #expect(flow.errorMessage == nil)
        #expect(flow.assignments == saved)
        #expect(fixture.hotkeys.registrations.count == 2)
    }
}

@MainActor
private final class Fixture {
    let directory: URL
    let store: AssignmentStore
    let workspace = FakeWorkspace()
    let hotkeys = FakeHotkeys()
    let app = SelectedApp(bundleIdentifier: "test.editor", url: URL(fileURLWithPath: "/Applications/Editor.app"), name: "Editor")

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = AssignmentStore(url: directory.appending(path: "assignments.json"))
        workspace.selections[app.url] = app
    }

    func flow(hotkeys: FakeHotkeys? = nil) -> AssignmentFlow {
        AssignmentFlow(store: store, hotkeys: hotkeys ?? self.hotkeys, workspace: workspace)
    }

    func record(_ flow: AssignmentFlow, keyCode: UInt16 = 0, characters: String = "a", flags: NSEvent.ModifierFlags = [.control, .option]) throws {
        flow.record(try event(.keyDown, keyCode: keyCode, characters: characters, flags: flags))
        flow.record(try event(.keyUp, keyCode: keyCode, characters: characters, flags: flags))
    }

    func event(_ type: NSEvent.EventType, keyCode: UInt16 = 0, characters: String = "a", flags: NSEvent.ModifierFlags = [.control, .option], isRepeat: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                                     windowNumber: 0, context: nil, characters: characters,
                                     charactersIgnoringModifiers: characters, isARepeat: isRepeat, keyCode: keyCode))
    }

    func removeFiles() {
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record(error) }
    }
}

@MainActor
private final class FakeHotkeys: HotkeyRegistry {
    struct Registration {
        let shortcut: Shortcut
        let action: @MainActor () -> Void
    }

    var registrations: [UUID: Registration] = [:]
    var rejectedKeys: Set<UInt16> = []
    var rejectUnregister = false
    var successfulUnregistrations = 0
    var failUnregisterAfter: Int?

    func register(_ shortcut: Shortcut, action: @escaping @MainActor () -> Void) throws -> UUID {
        guard !rejectedKeys.contains(shortcut.keyCode),
              !registrations.values.contains(where: { $0.shortcut.matches(shortcut) }) else {
            throw PeekabooError("Shortcut unavailable")
        }
        let id = UUID()
        registrations[id] = Registration(shortcut: shortcut, action: action)
        return id
    }

    func unregister(_ registration: UUID) throws {
        if rejectUnregister { throw PeekabooError("Cannot unregister shortcut") }
        if let failUnregisterAfter, successfulUnregistrations >= failUnregisterAfter {
            throw PeekabooError("Cannot unregister shortcut")
        }
        registrations.removeValue(forKey: registration)
        successfulUnregistrations += 1
    }
}

@MainActor
private final class FakeRunningApp: RunningApp {
    var isActive = false
    var isHidden = false
    var refuseHide = false
    var refuseActivation = false
    var activationOptions: NSApplication.ActivationOptions = []
    var appWindows = [AppWindow(id: UUID(), isMinimized: false, focusOrder: 1)]
    var windowError: PeekabooError?
    var restoreError: PeekabooError?

    func windows() throws -> [AppWindow] {
        if let windowError { throw windowError }
        return appWindows
    }

    func restoreWindow(_ id: UUID) throws {
        if let restoreError { throw restoreError }
        let order = (appWindows.compactMap(\.focusOrder).max() ?? 0) + 1
        appWindows = appWindows.map {
            $0.id == id ? AppWindow(id: id, isMinimized: false, focusOrder: order) : $0
        }
    }

    func hide() async -> Bool {
        guard !refuseHide else { return false }
        isHidden = true
        isActive = false
        return true
    }

    func activate(options: NSApplication.ActivationOptions) -> Bool {
        guard !refuseActivation else { return false }
        activationOptions = options
        isActive = true
        isHidden = false
        return true
    }
}

@MainActor
private final class FakeWorkspace: AppWorkspace {
    var accessibilityGranted = true
    var accessibilityRequested = false
    var trackedApps: [SelectedApp] = []
    var selections: [URL: SelectedApp] = [:]
    var running: [URL: FakeRunningApp] = [:]
    var launchError: PeekabooError?
    var launchContinuation: CheckedContinuation<Void, Never>?
    var holdLaunch = false
    var launched: [SelectedApp] = []
    private var launchObserver: CheckedContinuation<Void, Never>?

    func requestAccessibilityAccess() { accessibilityRequested = true }

    func trackApplications(_ apps: [SelectedApp]) { trackedApps = apps }

    func waitForLaunch() async {
        guard launched.isEmpty else { return }
        await withCheckedContinuation { launchObserver = $0 }
    }

    func selectApplication(at url: URL) throws -> SelectedApp {
        guard let app = selections[url] else { throw PeekabooError("Select an installed application") }
        return app
    }

    func runningApplication(for app: SelectedApp) throws -> (any RunningApp)? { running[app.url] }

    func launch(_ app: SelectedApp) async throws {
        launched.append(app)
        if holdLaunch {
            await withCheckedContinuation {
                launchContinuation = $0
                launchObserver?.resume()
                launchObserver = nil
            }
        } else {
            launchObserver?.resume()
            launchObserver = nil
        }
        if let launchError { throw launchError }
        let application = FakeRunningApp()
        application.isActive = true
        running[app.url] = application
    }
}
