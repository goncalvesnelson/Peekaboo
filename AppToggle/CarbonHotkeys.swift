import Carbon
import Foundation

private final class HotkeyCallback: Sendable {
    let receive: @MainActor @Sendable (UInt32, UInt32) -> Void

    init(receive: @escaping @MainActor @Sendable (UInt32, UInt32) -> Void) {
        self.receive = receive
    }
}

@MainActor
final class CarbonHotkeys: HotkeyRegistry {
    private struct Registration {
        let nativeID: UInt32
        let reference: EventHotKeyRef
        let action: @MainActor () -> Void
    }

    private var handler: EventHandlerRef?
    private var context: Unmanaged<HotkeyCallback>?
    private var registrations: [UUID: Registration] = [:]
    private var pressed: Set<UInt32> = []
    private var nextID: UInt32 = 1

    func register(_ shortcut: Shortcut, action: @escaping @MainActor () -> Void) throws -> UUID {
        try shortcut.validate()
        try installHandler()
        guard nextID < UInt32.max else {
            throw AppToggleError("The shortcut registration IDs are exhausted. Restart AppToggle.")
        }
        let nativeID = nextID
        nextID += 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), shortcut.modifiers,
            EventHotKeyID(signature: 0x41505447, id: nativeID),
            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference
        )
        guard status == noErr, let reference else {
            throw AppToggleError("macOS could not register \(shortcut.label) (status \(status)). Choose another shortcut.")
        }
        let id = UUID()
        registrations[id] = Registration(nativeID: nativeID, reference: reference, action: action)
        return id
    }

    func unregister(_ registration: UUID) throws {
        guard let entry = registrations[registration] else { return }
        let status = UnregisterEventHotKey(entry.reference)
        guard status == noErr else {
            throw AppToggleError("macOS could not release a shortcut (status \(status)). Quit and reopen AppToggle if retrying fails.")
        }
        pressed.remove(entry.nativeID)
        registrations.removeValue(forKey: registration)
    }

    func shutdown() throws {
        var failures: [String] = []
        for id in Array(registrations.keys) {
            do { try unregister(id) }
            catch { failures.append(error.localizedDescription) }
        }
        if let handler {
            let status = RemoveEventHandler(handler)
            if status == noErr {
                self.handler = nil
                context?.release()
                context = nil
                pressed.removeAll()
            } else {
                failures.append("macOS could not remove the shortcut handler (status \(status)).")
            }
        }
        guard failures.isEmpty else { throw AppToggleError(failures.joined(separator: "\n")) }
    }

    private func installHandler() throws {
        guard handler == nil else { return }
        let callback = HotkeyCallback { [weak self] id, kind in
            self?.receive(id: id, kind: kind)
        }
        let retained = Unmanaged.passRetained(callback)
        let types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData,
                  GetEventClass(event) == OSType(kEventClassKeyboard) else { return OSStatus(eventNotHandledErr) }
            let kind = GetEventKind(event)
            guard kind == UInt32(kEventHotKeyPressed) || kind == UInt32(kEventHotKeyReleased) else {
                return OSStatus(eventNotHandledErr)
            }
            var hotkey = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkey
            )
            guard status == noErr, hotkey.signature == 0x41505447 else { return OSStatus(eventNotHandledErr) }
            let receive = Unmanaged<HotkeyCallback>.fromOpaque(userData).takeUnretainedValue().receive
            let id = hotkey.id
            // Carbon lends the event and context only for this callback; queue copied values.
            DispatchQueue.main.async { receive(id, kind) }
            return noErr
        }, types.count, types, retained.toOpaque(), &handler)
        guard status == noErr else {
            retained.release()
            throw AppToggleError("macOS could not install the shortcut handler (status \(status)). Restart AppToggle and try again.")
        }
        context = retained
    }

    private func receive(id: UInt32, kind: UInt32) {
        guard let registration = registrations.values.first(where: { $0.nativeID == id }) else { return }
        if kind == UInt32(kEventHotKeyPressed) {
            pressed.insert(id)
            return
        }
        guard pressed.remove(id) != nil else { return }
        registration.action()
    }
}
