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
    func isMinimized(_ window: AXUIElement) throws -> Bool?
    func restoreWindow(_ window: AXUIElement) throws
}

@MainActor
final class AccessibilityWindows {
    private struct Window {
        let id: UUID
        let element: AXUIElement
        var focusOrder: UInt64?
    }

    private struct WindowState {
        let id: UUID
        let isMinimized: Bool
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
        let states = try readWindows()
        if access.isActive {
            do { try recordCurrentFocus(in: states) }
            catch {
                // A missed focus update must not discard the readable window snapshot.
            }
        }
        return states.map { state in
            AppWindow(
                id: state.id,
                isMinimized: state.isMinimized,
                focusOrder: knownWindows.first(where: { $0.id == state.id })?.focusOrder
            )
        }
    }

    func restoreWindow(_ id: UUID) throws {
        try start()
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
            let states = try readWindows()
            try recordCurrentFocus(in: states)
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

    private func readWindows() throws -> [WindowState] {
        var current: [Window] = []
        var states: [WindowState] = []
        for window in try access.windows() {
            let known = knownWindows.first(where: { CFEqual($0.element, window) })
                ?? Window(id: UUID(), element: window, focusOrder: nil)
            current.append(known)
            guard let minimized = try access.isMinimized(window) else { continue }
            states.append(WindowState(id: known.id, isMinimized: minimized))
        }
        knownWindows = current
        return states
    }

    private func recordCurrentFocus(in states: [WindowState]) throws {
        guard let focused = try access.focusedWindow(),
              let index = knownWindows.firstIndex(where: { CFEqual($0.element, focused) }),
              let state = states.first(where: { $0.id == knownWindows[index].id }),
              !state.isMinimized else { return }
        guard nextFocusOrder < UInt64.max else {
            throw PeekabooError("Window focus tracking is exhausted. Restart Peekaboo.")
        }
        nextFocusOrder += 1
        knownWindows[index].focusOrder = nextFocusOrder
    }
}
