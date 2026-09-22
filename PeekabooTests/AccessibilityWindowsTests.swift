import ApplicationServices
import Testing
@testable import Peekaboo

@MainActor
struct AccessibilityWindowsTests {
    @Test(arguments: [FocusFailure.start, .windows, .focusedWindow])
    func failedFocusObservationRetainsHistoryAndRecovers(failure: FocusFailure) throws {
        let access = FakeAccessibilityWindowAccess()
        let tracker = AccessibilityWindows(access: access)
        tracker.observeCurrentFocus()
        access.focused = access.second
        access.reportFocusChange()
        access.isActive = false
        let original = try tracker.windows()
        #expect(original.map(\.focusOrder) == [1, 2])

        access.isActive = true
        access.focused = access.first
        access.failure = failure
        access.reportFocusChange()
        #expect(access.failureCount == 1)
        access.failure = nil
        access.isActive = false
        #expect(try tracker.windows() == original)

        access.minimized = [access.first, access.second]
        let minimized = try tracker.windows()
        #expect(minimized.map(\.id) == original.map(\.id))
        #expect(minimized.map(\.focusOrder) == [1, 2])
        let recent = try #require(minimized.max { ($0.focusOrder ?? 0) < ($1.focusOrder ?? 0) })
        try tracker.restoreWindow(recent.id)
        let restored = try #require(access.restored)
        #expect(CFEqual(restored, access.second))
        #expect(try tracker.windows().map(\.isMinimized) == [true, false])

        access.minimized = []
        access.isActive = true
        access.reportFocusChange()
        access.isActive = false
        let recovered = try tracker.windows()
        #expect(recovered.map(\.id) == original.map(\.id))
        #expect(recovered.map(\.focusOrder) == [3, 2])
        try tracker.restoreWindow(recovered[0].id)
        let restoredFirst = try #require(access.restored)
        #expect(CFEqual(restoredFirst, access.first))
    }

    @Test func invalidWindowStateSkipsOnlyThatWindowAndPreservesIdentity() throws {
        let access = FakeAccessibilityWindowAccess()
        let tracker = AccessibilityWindows(access: access)
        tracker.observeCurrentFocus()
        access.isActive = false
        let original = try tracker.windows()

        access.failure = .invalidWindowState
        let available = try tracker.windows()
        #expect(available == [original[0]])
        #expect(access.failureCount == 1)

        access.failure = nil
        #expect(try tracker.windows() == original)
    }

    @Test func activeSnapshotAndRestorationEnumerateWindowsOnce() throws {
        let access = FakeAccessibilityWindowAccess()
        let tracker = AccessibilityWindows(access: access)

        let windows = try tracker.windows()
        #expect(access.windowListReadCount == 1)
        try tracker.restoreWindow(windows[0].id)
        #expect(access.windowListReadCount == 1)
    }

    @Test(arguments: [true, false])
    func permissionLossAndExplicitStopDiscardHistory(permissionLost: Bool) throws {
        let access = FakeAccessibilityWindowAccess()
        let tracker = AccessibilityWindows(access: access)
        tracker.observeCurrentFocus()
        access.isActive = false
        let original = try tracker.windows()
        #expect(original.first?.focusOrder == 1)

        if permissionLost {
            access.isTrusted = false
            access.reportFocusChange()
        } else {
            tracker.stop()
        }
        #expect(access.stopCount == 1)
        #expect(!access.isObserving)

        access.isTrusted = true
        let restarted = try tracker.windows()
        #expect(restarted.allSatisfy { $0.focusOrder == nil })
        #expect(Set(restarted.map(\.id)).isDisjoint(with: original.map(\.id)))
        #expect(access.isObserving)
        access.isActive = true
        access.focused = access.second
        access.reportFocusChange()
        access.isActive = false
        let refocused = try tracker.windows()
        #expect(refocused[0].focusOrder == nil)
        #expect(refocused[1].focusOrder != nil)
    }

    @Test func closedWindowsAreRemovedBeforeRestoration() throws {
        let access = FakeAccessibilityWindowAccess()
        let tracker = AccessibilityWindows(access: access)
        tracker.observeCurrentFocus()
        access.focused = access.second
        access.reportFocusChange()
        access.isActive = false
        let original = try tracker.windows()

        access.currentWindows = [access.first]
        #expect(try tracker.windows() == [original[0]])
        let readsBeforeRestore = access.windowListReadCount
        #expect(throws: PeekabooError.self) { try tracker.restoreWindow(original[1].id) }
        #expect(access.restored == nil)
        #expect(access.windowListReadCount == readsBeforeRestore)
        try tracker.restoreWindow(original[0].id)
        let restoredFirst = try #require(access.restored)
        #expect(CFEqual(restoredFirst, access.first))
    }
}

enum FocusFailure {
    case start
    case windows
    case focusedWindow
    case invalidWindowState
}

@MainActor
private final class FakeAccessibilityWindowAccess: AccessibilityWindowAccess {
    // Inert element handles provide distinct identities without querying another process.
    let first = AXUIElementCreateApplication(101)
    let second = AXUIElementCreateApplication(102)
    var isTrusted = true
    var isActive = true
    var currentWindows: [AXUIElement]
    var focused: AXUIElement?
    var minimized: [AXUIElement] = []
    var restored: AXUIElement?
    var failure: FocusFailure? {
        didSet { minimizedReadCount = 0 }
    }
    private(set) var failureCount = 0
    private(set) var stopCount = 0
    private(set) var windowListReadCount = 0
    private var minimizedReadCount = 0
    private var observeFocus: (@MainActor @Sendable () -> Void)?

    init() {
        currentWindows = [first, second]
        focused = first
    }

    var isObserving: Bool { observeFocus != nil }

    func start(observeFocus: @escaping @MainActor @Sendable () -> Void) throws {
        try fail(at: .start)
        guard self.observeFocus == nil else { return }
        self.observeFocus = observeFocus
    }

    func stop() {
        stopCount += 1
        observeFocus = nil
    }

    func reportFocusChange() { observeFocus?() }

    func windows() throws -> [AXUIElement] {
        windowListReadCount += 1
        try fail(at: .windows)
        return currentWindows
    }

    func focusedWindow() throws -> AXUIElement? {
        try fail(at: .focusedWindow)
        return focused
    }

    func isMinimized(_ window: AXUIElement) throws -> Bool? {
        minimizedReadCount += 1
        if minimizedReadCount == 2, failure == .invalidWindowState {
            failureCount += 1
            return nil
        }
        return minimized.contains { CFEqual($0, window) }
    }

    func restoreWindow(_ window: AXUIElement) throws {
        restored = window
        minimized.removeAll { CFEqual($0, window) }
    }

    private func fail(at point: FocusFailure) throws {
        guard failure == point else { return }
        failureCount += 1
        throw PeekabooError("Injected Accessibility timeout.")
    }
}
