import AppKit
import Carbon
import Testing
@testable import AppToggle

@Suite(.serialized)
@MainActor
struct NativeFlowTests {
    @Test func nativeSelectionAndRegistrationFailurePreserveSavedAssignment() throws {
        let directory = URL.temporaryDirectory.appending(path: "AppToggle-native-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let hotkeys = CarbonHotkeys()
        defer {
            do { try hotkeys.shutdown() }
            catch { Issue.record(error) }
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record(error) }
        }
        let store = AssignmentStore(url: directory.appending(path: "assignments.json"))
        let flow = AssignmentFlow(store: store, hotkeys: hotkeys, workspace: NativeWorkspace())
        flow.load()
        #expect(!flow.selectApplication(at: directory.appending(path: "invalid.txt")))
        #expect(flow.errorMessage?.contains("Choose an installed .app") == true)
        #expect(flow.selectApplication(at: URL(fileURLWithPath: "/System/Applications/TextEdit.app")))
        #expect(flow.selectedApp?.bundleIdentifier == "com.apple.TextEdit")
        flow.beginRecording()
        try record(flow, keyCode: UInt16(kVK_F19))
        try #require(flow.errorMessage == nil)
        let original = try #require(flow.assignments.first)
        #expect(original.shortcut.label == "⌃⌥⇧⌘F19")
        #expect(flow.errorMessage == nil)

        let occupied = Shortcut(keyCode: UInt16(kVK_F20), modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey), keyLabel: "F20")
        let competitor = try hotkeys.register(occupied) {}
        flow.beginRecording(for: original.id)
        try record(flow, keyCode: UInt16(kVK_F20))
        #expect(flow.assignments == [original])
        #expect(flow.errorMessage?.contains("could not register") == true)
        flow.load()
        #expect(flow.assignments == [original])

        try hotkeys.unregister(competitor)
        flow.beginRecording(for: original.id)
        try record(flow, keyCode: UInt16(kVK_F20))
        #expect(flow.assignments.first?.shortcut.matches(occupied) == true)
        #expect(flow.errorMessage == nil)
        let oldRegistration = try hotkeys.register(original.shortcut) {}
        try hotkeys.unregister(oldRegistration)

        flow.deleteAssignment(original.id)
        #expect(flow.assignments.isEmpty)
        #expect(flow.errorMessage == nil)
        flow.load()
        #expect(flow.assignments.isEmpty)
        let releasedShortcut = try hotkeys.register(occupied) {}
        try hotkeys.unregister(releasedShortcut)
    }

    private func record(_ flow: AssignmentFlow, keyCode: UInt16) throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try #require(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [.command, .control, .option, .shift],
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode
            ))
            flow.record(event)
        }
    }
}
