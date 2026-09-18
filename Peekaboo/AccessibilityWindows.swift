import AppKit
import ApplicationServices

private final class WindowFocusCallback: Sendable {
    let receive: @MainActor @Sendable () -> Void

    init(receive: @escaping @MainActor @Sendable () -> Void) {
        self.receive = receive
    }
}

@MainActor
final class AccessibilityWindows {
    private struct Window {
        let id: UUID
        let element: AXUIElement
        var focusOrder: UInt64?
    }

    private let application: NSRunningApplication
    private let appElement: AXUIElement
    private var knownWindows: [Window] = []
    private var nextFocusOrder: UInt64 = 0
    private var observer: AXObserver?
    private var context: Unmanaged<WindowFocusCallback>?

    init(application: NSRunningApplication) {
        self.application = application
        appElement = AXUIElementCreateApplication(application.processIdentifier)
    }

    func windows() throws -> [AppWindow] {
        try start()
        if application.isActive { observeCurrentFocus() }
        return try readWindows()
    }

    func restoreWindow(_ id: UUID) throws {
        try start()
        _ = try readWindows()
        guard let window = knownWindows.first(where: { $0.id == id }) else {
            throw PeekabooError("The selected window has closed. Try the shortcut again.")
        }
        try check(AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse),
                  operation: "restore the selected window")
        try check(AXUIElementPerformAction(window.element, kAXRaiseAction as CFString),
                  operation: "bring the selected window forward")
    }

    func observeCurrentFocus() {
        guard AXIsProcessTrustedWithOptions(nil) else {
            stop()
            return
        }
        do {
            try start()
            guard application.isActive else { return }
            _ = try readWindows()
            let value = try attribute(kAXFocusedWindowAttribute, of: appElement, allowNoValue: true)
            guard let value else { return }
            let focused = try element(value)
            guard let index = knownWindows.firstIndex(where: { CFEqual($0.element, focused) }),
                  try !isMinimized(focused) else { return }
            guard nextFocusOrder < UInt64.max else {
                throw PeekabooError("Window focus tracking is exhausted. Restart Peekaboo.")
            }
            nextFocusOrder += 1
            knownWindows[index].focusOrder = nextFocusOrder
        } catch {
            // A missed focus update makes earlier recency rankings unreliable.
            for index in knownWindows.indices { knownWindows[index].focusOrder = nil }
        }
    }

    func stop() {
        if let observer {
            let source = AXObserverGetRunLoopSource(observer)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        observer = nil
        context?.release()
        context = nil
        knownWindows.removeAll()
    }

    isolated deinit { stop() }

    private func start() throws {
        guard AXIsProcessTrustedWithOptions(nil) else {
            throw PeekabooError("Allow Peekaboo in System Settings → Privacy & Security → Accessibility to restore minimized windows.")
        }
        guard observer == nil else { return }
        try check(AXUIElementSetMessagingTimeout(appElement, 0.25), operation: "set up window access")
        var newObserver: AXObserver?
        let creation = AXObserverCreate(application.processIdentifier, { _, _, _, userData in
            guard let userData else { return }
            let receive = Unmanaged<WindowFocusCallback>.fromOpaque(userData).takeUnretainedValue().receive
            // This observer source is installed exclusively on the main run loop.
            MainActor.assumeIsolated { receive() }
        }, &newObserver)
        try check(creation, operation: "track window focus")
        guard let newObserver else {
            throw PeekabooError("macOS did not create a window focus observer.")
        }
        let callback = WindowFocusCallback { [weak self] in
            guard let self, self.observer != nil else { return }
            self.observeCurrentFocus()
        }
        let retained = Unmanaged.passRetained(callback)
        let registration = AXObserverAddNotification(
            newObserver, appElement, kAXFocusedWindowChangedNotification as CFString, retained.toOpaque()
        )
        guard registration == .success else {
            retained.release()
            try check(registration, operation: "track window focus")
            return
        }
        observer = newObserver
        context = retained
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
    }

    private func readWindows() throws -> [AppWindow] {
        guard let value = try attribute(kAXWindowsAttribute, of: appElement),
              let values = value as? [AnyObject] else {
            throw PeekabooError("The app returned an invalid window list.")
        }
        var current: [Window] = []
        var result: [AppWindow] = []
        for value in values {
            let window = try element(value)
            let subrole = try attribute(kAXSubroleAttribute, of: window, allowNoValue: true) as? String
            guard subrole == kAXStandardWindowSubrole else { continue }
            let minimized = try isMinimized(window)
            let known = knownWindows.first(where: { CFEqual($0.element, window) })
                ?? Window(id: UUID(), element: window, focusOrder: nil)
            current.append(known)
            result.append(AppWindow(id: known.id, isMinimized: minimized, focusOrder: known.focusOrder))
        }
        knownWindows = current
        return result
    }

    private func isMinimized(_ window: AXUIElement) throws -> Bool {
        guard let value = try attribute(kAXMinimizedAttribute, of: window),
              CFGetTypeID(value) == CFBooleanGetTypeID(), let minimized = value as? Bool else {
            throw PeekabooError("The app returned an invalid minimized-window state.")
        }
        return minimized
    }

    private func attribute(_ name: String, of element: AXUIElement, allowNoValue: Bool = false) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        if allowNoValue && status == .noValue { return nil }
        try check(status, operation: "read window information")
        return value
    }

    private func element(_ value: CFTypeRef) throws -> AXUIElement {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw PeekabooError("The app returned an invalid Accessibility window.")
        }
        let element = unsafeDowncast(value, to: AXUIElement.self)
        try check(AXUIElementSetMessagingTimeout(element, 0.25), operation: "set up window access")
        return element
    }

    private func check(_ status: AXError, operation: String) throws {
        guard status != .success else { return }
        let name = application.localizedName ?? "the app"
        throw PeekabooError("Peekaboo could not \(operation) for \(name) (Accessibility error \(status.rawValue)).")
    }
}
