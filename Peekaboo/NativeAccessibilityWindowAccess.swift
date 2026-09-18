import AppKit
import ApplicationServices

private final class WindowFocusCallback: Sendable {
    let receive: @MainActor @Sendable () -> Void

    init(receive: @escaping @MainActor @Sendable () -> Void) {
        self.receive = receive
    }
}

@MainActor
final class NativeAccessibilityWindowAccess: AccessibilityWindowAccess {
    private let application: NSRunningApplication
    private let appElement: AXUIElement
    private var observer: AXObserver?
    private var context: Unmanaged<WindowFocusCallback>?

    init(application: NSRunningApplication) {
        self.application = application
        appElement = AXUIElementCreateApplication(application.processIdentifier)
    }

    var isTrusted: Bool { AXIsProcessTrustedWithOptions(nil) }
    var isActive: Bool { application.isActive }

    func start(observeFocus: @escaping @MainActor @Sendable () -> Void) throws {
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
            observeFocus()
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

    func stop() {
        if let observer {
            let source = AXObserverGetRunLoopSource(observer)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        observer = nil
        context?.release()
        context = nil
    }

    isolated deinit { stop() }

    func windows() throws -> [AXUIElement] {
        guard let value = try attribute(kAXWindowsAttribute, of: appElement),
              let values = value as? [AnyObject] else {
            throw PeekabooError("The app returned an invalid window list.")
        }
        var windows: [AXUIElement] = []
        for value in values {
            let window = try element(value)
            let subrole = try attribute(kAXSubroleAttribute, of: window, allowNoValue: true) as? String
            guard subrole == kAXStandardWindowSubrole else { continue }
            windows.append(window)
        }
        return windows
    }

    func focusedWindow() throws -> AXUIElement? {
        guard let value = try attribute(kAXFocusedWindowAttribute, of: appElement, allowNoValue: true) else {
            return nil
        }
        return try element(value)
    }

    func restoreWindow(_ window: AXUIElement) throws {
        try check(AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse),
                  operation: "restore the selected window")
        try check(AXUIElementPerformAction(window, kAXRaiseAction as CFString),
                  operation: "bring the selected window forward")
    }

    func isMinimized(_ window: AXUIElement) throws -> Bool {
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
