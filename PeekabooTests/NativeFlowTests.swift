import AppKit
import Carbon
import SwiftUI
import Testing
@testable import Peekaboo

@Suite(.serialized)
@MainActor
struct NativeFlowTests {
    @Test func onlyInvalidAccessibilityElementsAreTreatedAsClosedWindows() {
        #expect(NativeAccessibilityWindowAccess.isClosedWindowError(.invalidUIElement))
        #expect(!NativeAccessibilityWindowAccess.isClosedWindowError(.cannotComplete))
    }

    @Test func trackedTerminationRefreshesWithoutBundleIdentifier() {
        let selectedBundleIdentifiers: Set<String> = ["test.editor"]

        #expect(NativeWorkspace.shouldRefreshApplications(
            for: NSWorkspace.didTerminateApplicationNotification,
            bundleIdentifier: nil,
            processIsTracked: true,
            selectedBundleIdentifiers: selectedBundleIdentifiers
        ))
        #expect(!NativeWorkspace.shouldRefreshApplications(
            for: NSWorkspace.didTerminateApplicationNotification,
            bundleIdentifier: nil,
            processIsTracked: false,
            selectedBundleIdentifiers: selectedBundleIdentifiers
        ))
        #expect(NativeWorkspace.shouldRefreshApplications(
            for: NSWorkspace.didActivateApplicationNotification,
            bundleIdentifier: "test.editor",
            processIsTracked: false,
            selectedBundleIdentifiers: selectedBundleIdentifiers
        ))
        #expect(!NativeWorkspace.shouldRefreshApplications(
            for: NSWorkspace.didActivateApplicationNotification,
            bundleIdentifier: nil,
            processIsTracked: true,
            selectedBundleIdentifiers: selectedBundleIdentifiers
        ))
    }

    @Test func settingsButtonBringsExistingWindowBackToFront() async throws {
        let menu = NSHostingMenu(rootView: SettingsButton())
        menu.update()
        let index = try #require(menu.items.firstIndex { $0.title == "Settings…" })
        let existing = Set(NSApplication.shared.windows.map(\.windowNumber))
        menu.performActionForItem(at: index)
        var settings: NSWindow?
        for _ in 0..<50 {
            settings = NSApplication.shared.windows.first {
                !existing.contains($0.windowNumber) && $0.isVisible && $0.canBecomeKey
            }
            if settings != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let settingsWindow = try #require(settings)
        defer { settingsWindow.close() }
        for _ in 0..<50 {
            if NSApplication.shared.isActive && settingsWindow.isKeyWindow { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(NSApplication.shared.isActive)
        try #require(settingsWindow.isKeyWindow)

        NSApplication.shared.hide(nil)
        for _ in 0..<50 {
            if !NSApplication.shared.isActive && NSApplication.shared.isHidden { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(!NSApplication.shared.isActive)
        try #require(NSApplication.shared.isHidden)
        NSApplication.shared.unhideWithoutActivation()
        for _ in 0..<50 {
            if !NSApplication.shared.isHidden { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(!NSApplication.shared.isHidden)
        try #require(settingsWindow.isVisible)
        try #require(!NSApplication.shared.isActive)
        menu.performActionForItem(at: index)
        for _ in 0..<50 {
            if NSApplication.shared.isActive && settingsWindow.isKeyWindow { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(NSApplication.shared.isActive)
        #expect(settingsWindow.isVisible)
        #expect(settingsWindow.isKeyWindow)
    }

    @Test func nativeSelectionAndRegistrationFailurePreserveSavedAssignment() throws {
        let directory = URL.temporaryDirectory.appending(path: "Peekaboo-native-\(UUID().uuidString)")
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
