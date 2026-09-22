# Native macOS APIs for Peekaboo

Research date: 2026-09-17. Scope: a native menu bar app with multiple app/shortcut assignments, whole-app hiding and activation, and best-effort conflict detection. No app implementation or interactive window tests were performed for this report. References include current Apple documentation and the installed Xcode 26.4.1 SDK headers.

## API selection

| Need | Apple API | Boundary |
| --- | --- | --- |
| Menu bar and settings | SwiftUI `MenuBarExtra`, `Settings`; AppKit where needed | `LSUIElement = true` hides Peekaboo from the Dock/app switcher. |
| Pick an app | `NSOpenPanel`, `allowedContentTypes = [.applicationBundle]` | Validate the selected bundle and its identifier. |
| Register global shortcuts | Carbon/HIToolbox `RegisterEventHotKey`, `InstallEventHandler` | Old C API, still declared without deprecation in the installed SDK. |
| Record a shortcut | Focused AppKit control with local `NSEvent` handling | SwiftUI menu shortcuts alone do not register a system-wide hotkey. |
| Detect configured system conflicts | `CopySymbolicHotKeys` | Partial coverage; no action names. |
| Locate/launch target | `NSRunningApplication`, `NSWorkspace` | App identity and multiple installed copies need a product decision. |
| Hide/show target | `hide()`, `unhide()`, `activate(options: [.activateAllWindows])` | Activation is a request, not a guarantee. |
| Persist assignments | Foundation `UserDefaults`, with typed data encoding if needed | Store settings, never process IDs or Carbon registration references. |
| Optional launch at login | `SMAppService.mainApp` | Add only if requested; registration status may require user action. |

Sources: [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra), [SDK hotkeys][hotkeys], [SDK application APIs][running], [SDK file-type filtering][panel], [UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults), [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice).

## Global registration and lifecycle

Install one handler on `GetApplicationEventTarget()` for `kEventClassKeyboard` and the chosen hotkey event kind. Register each assignment with its own `EventHotKeyID` and retain its `EventHotKeyRef`. The callback obtains the ID using `GetEventParameter` with `kEventParamDirectObject` / `typeEventHotKeyID`. Return `noErr` for an event handled by Peekaboo, and `eventNotHandledErr` for unrelated events. Pressed and released are distinct event types: do not toggle on both. The trigger timing and held-key behavior need a small probe before choosing between them. [SDK hotkey events][events], [SDK callback and handler lifecycle][handlers].

`RegisterEventHotKey`, `UnregisterEventHotKey`, `InstallEventHandler`, and `CopySymbolicHotKeys` are explicitly documented as not thread-safe. Proposed implementation: main-actor ownership of registration state and app actions. A C callback cannot capture Swift state normally; use a narrowly scoped callback bridge. Read and validate the Carbon parameters synchronously, then pass only a copied identifier into main-actor work. Never retain the callback's event or user-data pointer in an asynchronous task. Match any context allocation to explicit handler removal. This is implementation guidance derived from the C lifetime/threading contract, not a compiled bridge implementation. [SDK hotkeys][hotkeys], [SDK handlers][handlers].

On edit, attempt to register a different replacement combination before removing the old working registration. If registration fails, preserve the old assignment. On disable/delete, unregister the corresponding reference and check the status. Keep an assignment's configured value separate from whether its registration is active. On startup, an unavailable shortcut must not stop other assignments from registering. The OS removes registrations when the owning process exits. [SDK hotkeys][hotkeys].

## What conflict detection can promise

1. **Peekaboo duplicates:** compare normalized key code/modifier pairs across its assignments. This is fully under our control.
2. **Configured macOS symbolic shortcuts:** call `CopySymbolicHotKeys`, check its status, then compare only dictionaries with `kHISymbolicHotKeyEnabled = true`, using `kHISymbolicHotKeyCode` and `kHISymbolicHotKeyModifiers`. Release the copied array correctly. The SDK explicitly excludes application-specific customized commands and provides no way to map an entry to a named System Settings action. A truthful message is “This shortcut is assigned in macOS Keyboard Shortcuts.” [SDK symbolic hotkeys][symbolic].
3. **Other Carbon registrations:** request `kEventHotKeyExclusive` and handle registration failure. The SDK says ordinary registrations are non-exclusive: multiple applications may receive the same hotkey. Exclusive registration can prevent other registrants from receiving notifications while it is enabled. The option's descriptive comment says registration fails if the combination is already registered, while the return-code paragraph mentions existing exclusive registrations specifically; probe both cases rather than treating the narrower sentence as exhaustive. [SDK hotkeys][hotkeys].

There is no exhaustive conflict inventory in these APIs. Successful registration does not prove that a foreground app command, event-tap utility, or reserved system behavior cannot interfere. Nor does a registration error identify another app by name. Recheck known system conflicts when saving/re-enabling assignments and after returning to settings; avoid checking on every keystroke dispatch. If inspection fails, display an unavailable check, not “No conflicts.” The installed header lists `memFullErr` as a possible `CopySymbolicHotKeys` result. [SDK symbolic hotkeys][symbolic].

**Observed probe:** on 2026-09-17, the parent agent compiled and ran `CopySymbolicHotKeys` using Swift 6.3.1 on this macOS 26.6.2 host. Outside the tool execution sandbox, it returned status `0` and an array of 230 records. The same read-only probe inside the tool execution sandbox returned `-108` and no array. This verifies enumeration on this host; it does not establish record completeness, explain the failure's internal cause, or test an application using macOS App Sandbox. The probe used `takeRetainedValue()` for the returned copied array.

## Recording and displaying shortcuts

Use an AppKit recorder embedded in SwiftUI. A first-responder control can handle `keyDown`/`performKeyEquivalent`; a local event monitor is another option scoped strictly to an active recording session. Local monitors can consume the event and must be removed when finished. A global event monitor cannot suppress the original event and introduces keyboard-monitoring permission requirements, so it is not the registration mechanism for this app. [Apple event-monitoring guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html).

Store the virtual key code and normalized Command/Control/Option/Shift modifiers. Convert AppKit modifiers explicitly into Carbon's mask; their raw values are different representations. Treat left/right variants consistently, and avoid recording Caps Lock/device flags as ordinary shortcut modifiers. Proposed recorder behavior: Escape cancels, a separate clear action removes the assignment, and plain typing combinations are rejected by product policy. Temporarily suspend Peekaboo's own hotkeys during recording so recording an existing shortcut cannot switch apps; re-registration failures still need reporting.

For a live key event, use `NSEvent.characters(byApplyingModifiers:)` for its display label, with special-key names/glyphs handled separately. Apple now discourages `UCKeyTranslate` for ordinary event processing and points to this `NSEvent` method. `UCKeyTranslate` plus `TISCopyCurrentKeyboardLayoutInputSource` remains an option when a saved key code must be translated without a current event; verify that use with layout/IME tests and update labels on input-source changes. Do not hard-code a US key-code-to-letter table. [NSEvent translation](https://developer.apple.com/documentation/appkit/nsevent/characters(byapplyingmodifiers:)), [UCKeyTranslate](https://developer.apple.com/documentation/coreservices/1390584-uckeytranslate), [SDK input-source APIs][input].

**Version trap:** macOS 15 initially restricted Option/Option-Shift hotkeys. In the same Apple forum thread, an Apple engineer later stated that macOS 15.2 beta 2 restored them. Do not claim Command/Control is universally required on current macOS. If supporting 15.0–15.1, handle their restriction explicitly; probe the chosen minimum/current OS and sandbox configuration. [Apple engineer's original answer and later correction](https://developer.apple.com/forums/thread/763878).

## Whole-app toggling and its limits

Proposed behavior: look up the selected running application at each trigger. If it is active, request `hide()`. Otherwise, unhide it when needed and request `activate(options: [.activateAllWindows])`. Decide separately whether an app that is not running should launch. Use observed app state, not an internal alternating “shown/hidden” flag: users can switch and hide apps independently. The SDK notes that state observations update across main-run-loop turns. [SDK application APIs][running].

The all-windows option is documented to bring all the application's windows forward instead of only its main/key windows. It is not a documented guarantee to deminimize every window, create a window when none exists, leave fullscreen, or move windows between Spaces. Those are separate behaviors, and this report does not claim they work. Spaces have their own assignment and switching settings; activation can switch to a Space with existing windows depending on those settings. Test fullscreen, minimized-only apps, multiple displays, and Stage Manager before describing the experience as identical to iTerm's hotkey window. [SDK activation options][running], [Apple Spaces guide](https://support.apple.com/en-euro/guide/mac-help/mh14112/mac).

From macOS 14, activation follows user intent and may be refused. `activateIgnoringOtherApps` is deprecated and the installed SDK says it has no effect. Cooperative activation uses `yieldActivation(to:)` and `activate(from:options:)` when the giving app participates. Peekaboo cannot make an arbitrary foreground app yield; a global-hotkey trigger from an accessory app therefore needs an actual activation probe. Check return values and workspace activation notifications; a successful request is not evidence that the target is already frontmost. [AppKit macOS 14 release notes](https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-14), [SDK application APIs][running].

## App selection, identity, and launch

`NSOpenPanel` can select an application bundle without requiring a custom installed-app index. Read its bundle identifier and display name; reject non-app selections and unsuitable targets such as Peekaboo itself. A running-app list is an optional convenience, not a substitute for selecting apps that are currently closed. [SDK panel][panel], [NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication).

Persist the selected bundle identifier and, if exact installed-copy identity matters, its selected URL/bookmark. `runningApplications(withBundleIdentifier:)` returns an array: a bundle identifier is not a guaranteed unique running process. `NSWorkspace.urlForApplication(withBundleIdentifier:)` chooses a default using heuristics when multiple copies exist. Decide whether an assignment follows that default or the particular copy selected. Do not silently pick an unrelated copy after a path disappears. [SDK application APIs][running], [NSWorkspace resolution](https://developer.apple.com/documentation/appkit/nsworkspace/urlforapplication(withbundleidentifier:)).

If launching is included, use `NSWorkspace.openApplication(at:configuration:)` with activation enabled and no request for a new instance. Its async form reports launch failure. The completion-handler form runs on a concurrent queue, so update UI and actor-owned state on the main actor. Serialize repeated triggers while a launch request is outstanding, then derive the next action from actual app state. [NSWorkspace launch](https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:completionhandler:)).

## Permissions and packaging

The proposed core uses Carbon hotkey registration and AppKit app operations, not Accessibility window traversal, AppleScript, or global keyboard monitoring. Those selected API declarations do not document an Accessibility/Input Monitoring prompt. Treat “no special permissions required” as a hypothesis to verify with a fresh signed app that has no existing grants, not as proven by this research. App Sandbox behavior must also be checked in the intended app target.

App Store distribution requires App Sandbox; Apple's sandbox guide lists assistive Accessibility APIs and sending Apple Events to arbitrary apps among incompatible activities. Selecting application bundles through the standard file panel is the native sandbox access path. Persistent access to an exact selected file may need a security-scoped bookmark. Do not add broad automation/accessibility permissions as speculative workarounds for activation. [App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox), [sandbox resource access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).

Use a regular macOS application target in Xcode so the bundle identity, `LSUIElement`, entitlements, signing, and settings lifecycle are explicit. SwiftUI plus a small AppKit/Carbon boundary is sufficient; no third-party package or helper daemon is required by the API surface above. This is an implementation recommendation, not a distribution/signing setup completed by this research.

## Decisions and evidence still needed

Before implementation, settle these product choices:

- Launch closed apps, or operate only on running apps.
- Preserve minimized/fullscreen/Spaces placement, or require window manipulation beyond whole-app activation.
- Follow bundle identity, or bind each assignment to the selected installed copy.
- Support older macOS versions, or target only the versions available for testing.
- Block known system conflicts, or allow an explicit override where registration permits it.

The key probe should exercise registration → physical shortcut → activate every normal window → shortcut → hide, across two target apps, with no preexisting privacy grants. Also verify duplicate/exclusive registrations between two processes, recorder suspension/resumption, physical Option/Option-Shift delivery, non-US layouts, restart persistence, launch failure, and fullscreen/minimized/Spaces behavior. These are remaining verification tasks, not results. Automated pure-logic checks cannot establish cross-app focus or OS shortcut interception behavior.

Follow-up verification on 2026-09-22 established symbolic-hotkey enumeration, including enabled entries, and exclusive Option/Option-Shift registration on this host. The signed native flow test also confirmed same-process exclusive collisions. Physical delivery and cross-process behavior remain unverified; see [native checks](../native-checks.md).

[hotkeys]: /Applications/Xcode-26.4.1.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/CarbonEvents.h:15390
[symbolic]: /Applications/Xcode-26.4.1.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/CarbonEvents.h:15525
[events]: /Applications/Xcode-26.4.1.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/CarbonEvents.h:4675
[handlers]: /Applications/Xcode-26.4.1.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/CarbonEventsCore.h:2445
[running]: /Applications/Xcode-26.4.1.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSRunningApplication.h:16
[panel]: /Applications/Xcode-26.4.1.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSSavePanel.h:60
[input]: /Applications/Xcode-26.4.1.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/TextInputSources.h:803
