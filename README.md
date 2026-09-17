# AppToggle

A native macOS 26 menu bar app that pairs an installed app with a global shortcut. Use the shortcut to launch a closed app, bring a background app forward, or hide the focused app.

AppToggle uses SwiftUI, AppKit, and Carbon/HIToolbox, with no third-party dependencies. This personal-use build uses ad hoc signing and runs outside App Sandbox. It does not request Accessibility or Input Monitoring access.

## Build and test

Requires Xcode 26 with its command-line tools selected and macOS 26. The development host has Xcode 26.4.1 and macOS 26.6.2.

```sh
make build
make test
make run
```

`make check` runs the same build-and-test pass as `make test`. Both Swift and Clang treat compiler warnings as errors. These commands use the shared `AppToggle` scheme, a macOS destination matching the host architecture, and `.build/` for derived data. On this Apple silicon Mac, the canonical underlying commands are:

```sh
xcodebuild -project AppToggle.xcodeproj -scheme AppToggle -destination 'platform=macOS,arch=arm64' -derivedDataPath .build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES build
xcodebuild -project AppToggle.xcodeproj -scheme AppToggle -destination 'platform=macOS,arch=arm64' -derivedDataPath .build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES test
```

Tests use temporary configuration files. The scheme sets `APPTOGGLE_TESTING=1` in the test host so it does not restore your own assignments or register their shortcuts.

## Assign an app

Open **AppToggle → Settings…** from the menu bar, choose an installed `.app`, and click **Record Shortcut…**. Press a key with Command, Control, or Option, then release the key to save. Escape, Cancel, closing settings, or switching away from AppToggle cancels recording. AppToggle suspends its own shortcuts during recording and restores them afterward.

Use **Change Shortcut…** beside an assignment to edit it. A rejected replacement keeps the previous assignment. Errors appear in settings and the menu bar; a failed startup registration leaves the assignment visible for correction. Choosing the same shortcut again retries its registration.

**Delete Shortcut** removes the app–shortcut pairing and releases its global shortcut. If saving fails, the assignment stays usable. If macOS cannot release a deleted shortcut, AppToggle reports the cleanup error; use **Reload Saved Assignments** to retry.

Assignments target the installed copy you selected, identified by its file URL and bundle identifier. If that copy moves or disappears, use **Choose App…** beside the assignment to select it again and record its shortcut. AppToggle will not silently launch another installed copy. You can add more than one assignment; each shortcut must be unique within AppToggle.

Configuration lives at `~/Library/Application Support/AppToggle/assignments.json`. Writes replace the file atomically. A failed read blocks saving to protect the existing file; correct the reported file problem and use **Reload Saved Assignments**. A failed write leaves the previous saved assignment intact.

## Native behavior and limits

Each completed shortcut gesture requests one app toggle. AppToggle checks the app's current state for every gesture, including changes made outside AppToggle, and suppresses repeated launch requests while one is outstanding.

Activation requests bring all non-minimized windows forward. AppToggle does not restore minimized windows, change window positions, or move windows between Spaces. macOS controls Space switching. A successful native activation request is not a guarantee of immediate focus; AppToggle reports rejected requests.

Shortcut labels reflect the keyboard layout used during recording. Command, Control, Option, and Shift flags are normalized; the label includes recognizable names or glyphs for special keys. Shortcuts use physical key codes, so re-record them if you change layouts and want a different physical combination.

This slice handles registration failures and AppToggle's own duplicate shortcuts. Configured macOS system-conflict warnings are separate work. A successful registration does not prove that macOS or another app cannot intercept the combination.

See [native checks](docs/native-checks.md) for interactive steps and recorded results. Passing automated tests does not establish physical global shortcut delivery, window behavior, or Space switching.
