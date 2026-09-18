# Native checks

Target host: macOS 26.6.2 (25G83), Xcode 26.4.1 (17E202). The environment versions were read on 2026-09-18. These checks use the built app from `make run`.

## Completed observations

After the review fixes and Settings activation fix, `make check` passed all 28 tests with compiler warnings treated as errors. Updated flow cases cover active apps with no standard windows, independent Settings and per-assignment toggle errors, successful retry cleanup, assignment removal and replacement, pending launch completion after deletion, and the menu-bar warning while Accessibility is denied.

The focus tracker now has an injectable Accessibility boundary. Automated tests establish two window rankings, inject failures during observer startup, window enumeration, focused-window lookup and minimized-state reads, and verify that rankings and window identities survive. They also cover restoration, later focus updates, permission loss, explicit stop and closed windows. Restoring the old history-clearing catch made all five failure cases fail; the retained-history implementation passes. These checks use inert element handles and fake Accessibility responses, so they do not require a permission grant or establish native window behavior.

The Settings regression invokes the real SwiftUI button through `NSHostingMenu`, opens Settings, leaves its window visible while the app is inactive, and invokes the menu action again. It verifies that the same window becomes key and Peekaboo becomes active. The original `SettingsLink` and appearance-only activation failed this check. `NSApplication.activate()` and `NSRunningApplication.activate(options:)` also left the test host inactive; explicit `NSApplication.activate(ignoringOtherApps: true)` succeeded. The production action uses explicit activation only in response to selecting Settings. The permission button after a prior denial remains unverified.

After the Peekaboo rename and icon additions, `make check build app install` passed all 24 tests and both build configurations. `/Applications/Peekaboo.app` passed strict signature verification and opened. Its compiled catalog contains the app icon and the custom menu bar icon as a preserved vector template with 1× and 2× representations. Saved assignments retain their existing storage location.

Before the Peekaboo rename, adding explicit window restoration passed `make check build app install` with all 24 tests, built Debug and Release with compiler warnings treated as errors, verified the Release signature, and installed `/Applications/AppToggle.app`. The installed copy passed `codesign --verify --strict` and opened successfully. Flow tests cover selecting one recent window, repeated hide/return without restoring older windows, active apps with all windows minimized, missing history, denied access, and failed restoration. Native Accessibility manipulation remains unverified pending the permission grant and interactive checks below.

A disposable two-window AppKit probe confirmed that ordinary activation left both minimized windows minimized, native reopening restored the recent window only when both were minimized, and activation unhides a hidden app. Because applications control reopening, the user chose explicit Accessibility window selection and focus tracking instead. The probe did not test the new Accessibility implementation.

Before the explicit-window-restoration change, `make check` passed all 21 tests with compiler warnings treated as errors. `make build` passed. These results cover the implementation and native API checks described below, not the unperformed interactive checks.

On 2026-09-18, the user selected Mail at `/System/Applications/Mail.app`, recorded ⌥⌘period, and exercised the physical shortcut. The active input source read during this session was U.S. (`com.apple.keylayout.US`). Mail's assignment survived application restarts.

The first build required two gestures to return hidden Mail. A temporary native trace showed every press/release pair reaching the app, but `unhide()` returned `false` while Mail changed from hidden to unhidden. The flow stopped before activation. A standalone AppKit probe reproduced the return value and showed that direct `activate(options: [.activateAllWindows])` both unhides and activates Mail. The same probe found `hide()` returning `false` even when Mail became hidden on a later run-loop turn.

The implementation now activates background apps directly and, after a false hide return, waits up to one second for the observed hidden state before reporting failure. The user tested the corrected build and confirmed that repeated gestures hide and return Mail correctly. Temporary logging was removed. [Apple documents that running-app state updates across main-run-loop turns](https://developer.apple.com/documentation/appkit/nsrunningapplication).

Automated native checks exercise TextEdit bundle selection, invalid selection errors, function-key recording, actual Carbon registration collisions, preservation of a failed replacement, successful replacement, and release after deletion. These checks do not synthesize physical keyboard input or assert window visibility.

## Interactive procedure

Use a target app with disposable documents, such as TextEdit. Keep any existing documents untouched. Explicit restoration now requires Accessibility access for Peekaboo. Enable it from Peekaboo settings before checking minimized windows. Input Monitoring and AppleScript are not used.

| Check | Steps | Result |
| --- | --- | --- |
| Menu bar and picker | Open settings from the menu bar; choose a closed installed app. Confirm the name and selected path. Try an invalid bundle and confirm an actionable error. | Menu bar, Mail selection and recording completed by user. Closed-app selection and invalid-bundle GUI checks unverified; native API selection tests cover valid/invalid paths. |
| Existing Settings window | Leave Settings open behind another app, then select Settings from Peekaboo's menu again. Confirm the existing window comes forward and receives focus. | Automated native menu-action regression passes; physical menu click remains an interactive check. |
| Physical global delivery | Record an unused shortcut, focus another app, press and release it. Confirm the target launches or activates. Hold the shortcut before releasing and confirm it toggles once. | Mail activation completed with ⌥⌘period. Physical held-key and closed-app launch checks unverified. |
| Hiding and current state | With the target focused, repeat the shortcut to hide it. Switch or hide apps independently, then repeat; confirm the action follows current focus. | Repeated Mail hiding/return completed after the native fix. Independent external-hide sequence unverified. |
| Multiple normal windows | Open two disposable target windows. Cover both with another app, then trigger the target shortcut; confirm both normal windows come forward. | Unverified |
| Recent minimized window | With Accessibility enabled, focus two target windows in order and minimize both. Trigger the shortcut; only the recent window should return. Toggle twice more and confirm the older window remains minimized. Repeat while the app remains active with all windows minimized. | Unverified |
| Unknown window history | Start Peekaboo with several target windows already minimized. Confirm an actionable history error instead of guessing. Open one window, minimize it, and retry. | Unverified |
| No standard windows | With Accessibility enabled, close the target's disposable document windows while leaving it active. Trigger its shortcut and confirm it hides; repeat to activate, then hide again. | Unverified |
| Permission and window failures | Deny or revoke Accessibility; confirm the menu-bar warning remains while ordinary toggles work without losing assignments. Grant access and trigger again; confirm the permission warning clears. Close a tracked window and use the next most recent surviving window. | Unverified |
| Permission button after denial | With the installed Peekaboo already denied access, click Allow Accessibility and record whether a system dialog or Settings window appears. | Unverified. The API returns current trust, not whether the asynchronous prompt appeared. |
| Independent error recovery | Cause toggle errors for two assignments. Retry one successfully and confirm only its error clears. Confirm Settings actions leave toggle errors visible and successful toggles leave Settings errors visible. | Unverified |
| Window geometry | Note positions, restore the recent minimized window, and toggle twice; confirm no window positions change. | Unverified |
| Spaces | Put target windows on different Spaces. Trigger from another Space and check normal macOS switching behavior; confirm each window retains its Space. | Unverified |
| Keyboard layout | Record a printable key, an Option combination, and an Option-Shift combination on the active layout. Confirm labels and actual delivery. Note the input source used. | U.S. layout, ⌥⌘period recorded and delivered. Option-only, Option-Shift and other layouts unverified. |
| Recording lifecycle | Start editing an existing shortcut and try it while recording. Cancel with Escape and then by switching apps. Confirm the old shortcut works afterward. Close settings during recording and repeat. | Unverified |
| Persistence and replacement | Save an assignment, quit and reopen Peekaboo, and use it. Edit its shortcut; confirm the new combination works and the old one no longer does. | Mail assignment restored across app restarts and remained usable. Physical replacement check unverified; automated flow/native registration checks pass. |
| Deletion | Delete an assignment, confirm the row disappears and the shortcut stops toggling, then restart. | Automated flow and native release check; interactive check unverified. |
| Failure visibility | Attempt a combination registered by another app; confirm the rejection is visible and the previous shortcut still works. Test a missing selected copy without moving a real installed app. | Unverified |

Record the active keyboard layout, shortcut combinations, target app, and observations when completing these checks. A synthetic Carbon event only checks handler dispatch; it cannot prove physical delivery. AppKit request return values likewise do not prove that a window became visible.

If an interactive check demonstrates a native limitation, record reproduction steps and investigate the API before changing behavior or adding permissions.
