# Native checks

Target host: macOS 26.6.2 (25G83), Xcode 26.4.1 (17E202). The environment versions were read on 2026-09-18. These checks use the built app from `make run`.

## Completed observations

After adding explicit window restoration, `make check build app install` passed all 24 tests, built Debug and Release with compiler warnings treated as errors, verified the Release signature, and installed `/Applications/AppToggle.app`. The installed copy passed `codesign --verify --strict` and opened successfully. Flow tests cover selecting one recent window, repeated hide/return without restoring older windows, active apps with all windows minimized, missing history, denied access, and failed restoration. Native Accessibility manipulation remains unverified pending the permission grant and interactive checks below.

A disposable two-window AppKit probe confirmed that ordinary activation left both minimized windows minimized, native reopening restored the recent window only when both were minimized, and activation unhides a hidden app. Because applications control reopening, the user chose explicit Accessibility window selection and focus tracking instead. The probe did not test the new Accessibility implementation.

Before the explicit-window-restoration change, `make check` passed all 21 tests with compiler warnings treated as errors. `make build` passed. These results cover the implementation and native API checks described below, not the unperformed interactive checks.

On 2026-09-18, the user selected Mail at `/System/Applications/Mail.app`, recorded ⌥⌘period, and exercised the physical shortcut. The active input source read during this session was U.S. (`com.apple.keylayout.US`). Mail's assignment survived AppToggle restarts.

The first build required two gestures to return hidden Mail. A temporary native trace showed every press/release pair reaching the app, but `unhide()` returned `false` while Mail changed from hidden to unhidden. The flow stopped before activation. A standalone AppKit probe reproduced the return value and showed that direct `activate(options: [.activateAllWindows])` both unhides and activates Mail. The same probe found `hide()` returning `false` even when Mail became hidden on a later run-loop turn.

The implementation now activates background apps directly and, after a false hide return, waits up to one second for the observed hidden state before reporting failure. The user tested the corrected build and confirmed that repeated gestures hide and return Mail correctly. Temporary logging was removed. [Apple documents that running-app state updates across main-run-loop turns](https://developer.apple.com/documentation/appkit/nsrunningapplication).

Automated native checks exercise TextEdit bundle selection, invalid selection errors, function-key recording, actual Carbon registration collisions, preservation of a failed replacement, successful replacement, and release after deletion. These checks do not synthesize physical keyboard input or assert window visibility.

## Interactive procedure

Use a target app with disposable documents, such as TextEdit. Keep any existing documents untouched. Explicit restoration now requires Accessibility access for AppToggle. Enable it from AppToggle settings before checking minimized windows. Input Monitoring and AppleScript are not used.

| Check | Steps | Result |
| --- | --- | --- |
| Menu bar and picker | Open settings from the menu bar; choose a closed installed app. Confirm the name and selected path. Try an invalid bundle and confirm an actionable error. | Menu bar, Mail selection and recording completed by user. Closed-app selection and invalid-bundle GUI checks unverified; native API selection tests cover valid/invalid paths. |
| Physical global delivery | Record an unused shortcut, focus another app, press and release it. Confirm the target launches or activates. Hold the shortcut before releasing and confirm it toggles once. | Mail activation completed with ⌥⌘period. Physical held-key and closed-app launch checks unverified. |
| Hiding and current state | With the target focused, repeat the shortcut to hide it. Switch or hide apps independently, then repeat; confirm the action follows current focus. | Repeated Mail hiding/return completed after the native fix. Independent external-hide sequence unverified. |
| Multiple normal windows | Open two disposable target windows. Cover both with another app, then trigger the target shortcut; confirm both normal windows come forward. | Unverified |
| Recent minimized window | With Accessibility enabled, focus two target windows in order and minimize both. Trigger the shortcut; only the recent window should return. Toggle twice more and confirm the older window remains minimized. Repeat while the app remains active with all windows minimized. | Unverified |
| Unknown window history | Start AppToggle with several target windows already minimized. Confirm an actionable history error instead of guessing. Open one window, minimize it, and retry. | Unverified |
| Permission and window failures | Deny or revoke Accessibility; confirm visible errors without losing assignments. Close a tracked window and use the next most recent surviving window. | Unverified |
| Window geometry | Note positions, restore the recent minimized window, and toggle twice; confirm no window positions change. | Unverified |
| Spaces | Put target windows on different Spaces. Trigger from another Space and check normal macOS switching behavior; confirm each window retains its Space. | Unverified |
| Keyboard layout | Record a printable key, an Option combination, and an Option-Shift combination on the active layout. Confirm labels and actual delivery. Note the input source used. | U.S. layout, ⌥⌘period recorded and delivered. Option-only, Option-Shift and other layouts unverified. |
| Recording lifecycle | Start editing an existing shortcut and try it while recording. Cancel with Escape and then by switching apps. Confirm the old shortcut works afterward. Close settings during recording and repeat. | Unverified |
| Persistence and replacement | Save an assignment, quit and reopen AppToggle, and use it. Edit its shortcut; confirm the new combination works and the old one no longer does. | Mail assignment restored across app restarts and remained usable. Physical replacement check unverified; automated flow/native registration checks pass. |
| Deletion | Delete an assignment, confirm the row disappears and the shortcut stops toggling, then restart. | Automated flow and native release check; interactive check unverified. |
| Failure visibility | Attempt a combination registered by another app; confirm the rejection is visible and the previous shortcut still works. Test a missing selected copy without moving a real installed app. | Unverified |

Record the active keyboard layout, shortcut combinations, target app, and observations when completing these checks. A synthetic Carbon event only checks handler dispatch; it cannot prove physical delivery. AppKit request return values likewise do not prove that a window became visible.

If an interactive check demonstrates a native limitation, record reproduction steps and investigate the API before changing behavior or adding permissions.
