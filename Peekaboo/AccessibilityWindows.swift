import AppKit
import ApplicationServices

@MainActor
protocol AccessibilityWindowAccess: AnyObject {
    var isTrusted: Bool { get }
    var isActive: Bool { get }
    func start(observeFocus: @escaping @MainActor @Sendable () -> Void) throws
    func stop()
    func windows() throws -> [AXUIElement]
    func focusedWindow() throws -> AXUIElement?
    func isMinimized(_ window: AXUIElement) throws -> Bool
    func restoreWindow(_ window: AXUIElement) throws
}

@MainActor
final class AccessibilityWindows {
    private struct Window {
        let id: UUID
        let element: AXUIElement
        var focusOrder: UInt64?
    }

    private let access: any AccessibilityWindowAccess
    private var knownWindows: [Window] = []
    private var nextFocusOrder: UInt64 = 0

    convenience init(application: NSRunningApplication) {
        self.init(access: NativeAccessibilityWindowAccess(application: application))
    }

    init(access: any AccessibilityWindowAccess) {
        self.access = access
    }

    func windows() throws -> [AppWindow] {
        try start()
        if access.isActive { observeCurrentFocus() }
        return try readWindows()
    }

    func restoreWindow(_ id: UUID) throws {
        try start()
        _ = try readWindows()
        guard let window = knownWindows.first(where: { $0.id == id }) else {
            throw PeekabooError("The selected window has closed. Try the shortcut again.")
        }
        try access.restoreWindow(window.element)
    }

    func observeCurrentFocus() {
        guard access.isTrusted else {
            stop()
            return
        }
        do {
            try start()
            guard access.isActive else { return }
            _ = try readWindows()
            guard let focused = try access.focusedWindow() else { return }
            guard let index = knownWindows.firstIndex(where: { CFEqual($0.element, focused) }),
                  try !access.isMinimized(focused) else { return }
            guard nextFocusOrder < UInt64.max else {
                throw PeekabooError("Window focus tracking is exhausted. Restart Peekaboo.")
            }
            nextFocusOrder += 1
            knownWindows[index].focusOrder = nextFocusOrder
        } catch {
            // Keep the last observed order even if a focus change was missed.
            return
        }
    }

    func stop() {
        access.stop()
        knownWindows.removeAll()
    }

    isolated deinit { stop() }

    private func start() throws {
        try access.start { [weak self] in self?.observeCurrentFocus() }
    }

    private func readWindows() throws -> [AppWindow] {
        var current: [Window] = []
        var result: [AppWindow] = []
        for window in try access.windows() {
            let minimized = try access.isMinimized(window)
            let known = knownWindows.first(where: { CFEqual($0.element, window) })
                ?? Window(id: UUID(), element: window, focusOrder: nil)
            current.append(known)
            result.append(AppWindow(id: known.id, isMinimized: minimized, focusOrder: known.focusOrder))
        }
        knownWindows = current
        return result
    }
}
