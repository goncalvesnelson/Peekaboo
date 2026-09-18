import AppKit
import Carbon

struct SelectedApp: Codable, Equatable, Sendable {
    let bundleIdentifier: String
    let url: URL
    let name: String
}

struct Assignment: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let app: SelectedApp
    let shortcut: Shortcut
}

struct Shortcut: Codable, Equatable, Sendable {
    let keyCode: UInt16
    let modifiers: UInt32
    let keyLabel: String

    var label: String {
        var result = ""
        for (mask, symbol) in [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")] {
            if modifiers & UInt32(mask) != 0 { result += symbol }
        }
        return result + keyLabel
    }

    func matches(_ other: Shortcut) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    func validate() throws {
        let allowed = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        guard keyCode <= 127, modifiers & ~allowed == 0,
              modifiers & UInt32(cmdKey | controlKey | optionKey) != 0,
              !keyLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppToggleError("Use a key with Command, Control, or Option. Escape cancels recording.")
        }
    }

    init(keyCode: UInt16, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    init(event: NSEvent) throws {
        keyCode = event.keyCode
        var normalized: UInt32 = 0
        let modifierMasks: [(NSEvent.ModifierFlags, Int)] = [
            (.command, cmdKey), (.control, controlKey), (.option, optionKey), (.shift, shiftKey)
        ]
        for (flag, mask) in modifierMasks {
            if event.modifierFlags.contains(flag) { normalized |= UInt32(mask) }
        }
        modifiers = normalized

        switch Int(event.keyCode) {
        case kVK_Return: keyLabel = "↩"
        case kVK_Tab: keyLabel = "⇥"
        case kVK_Space: keyLabel = "Space"
        case kVK_Delete: keyLabel = "⌫"
        case kVK_ForwardDelete: keyLabel = "⌦"
        case kVK_LeftArrow: keyLabel = "←"
        case kVK_RightArrow: keyLabel = "→"
        case kVK_UpArrow: keyLabel = "↑"
        case kVK_DownArrow: keyLabel = "↓"
        case kVK_Home: keyLabel = "Home"
        case kVK_End: keyLabel = "End"
        case kVK_PageUp: keyLabel = "Page Up"
        case kVK_PageDown: keyLabel = "Page Down"
        case kVK_Help: keyLabel = "Help"
        case kVK_ANSI_KeypadEnter: keyLabel = "⌤"
        default:
            let functionKeys = [
                kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
            ]
            if let index = functionKeys.firstIndex(of: Int(event.keyCode)) {
                keyLabel = "F\(index + 1)"
            } else {
                let characters = event.characters(byApplyingModifiers: []) ?? ""
                guard !characters.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                    throw AppToggleError("This key has no displayable shortcut label. Choose another key.")
                }
                keyLabel = characters.uppercased()
            }
        }
        try validate()
    }
}

struct AppToggleError: LocalizedError {
    let message: String

    init(_ message: String) { self.message = message }

    var errorDescription: String? { message }
}

@MainActor
protocol HotkeyRegistry: AnyObject {
    func register(_ shortcut: Shortcut, action: @escaping @MainActor () -> Void) throws -> UUID
    func unregister(_ registration: UUID) throws
}

@MainActor
protocol RunningApp: AnyObject {
    var isActive: Bool { get }
    func windows() throws -> [AppWindow]
    func restoreWindow(_ id: UUID) throws
    func hide() async -> Bool
    func activate(options: NSApplication.ActivationOptions) -> Bool
}

struct AppWindow: Equatable {
    let id: UUID
    let isMinimized: Bool
    let focusOrder: UInt64?
}

@MainActor
protocol AppWorkspace {
    var accessibilityGranted: Bool { get }
    func requestAccessibilityAccess()
    func trackApplications(_ apps: [SelectedApp])
    func selectApplication(at url: URL) throws -> SelectedApp
    func runningApplication(for app: SelectedApp) throws -> (any RunningApp)?
    func launch(_ app: SelectedApp) async throws
}
