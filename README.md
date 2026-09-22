# Peekaboo

A native macOS 26 menu bar app that pairs an installed app with a global shortcut. Use the shortcut to launch a closed app, bring a background app forward, or hide the focused app.

Peekaboo uses SwiftUI, AppKit, and Carbon/HIToolbox, with no third-party dependencies. Local builds use a self-signed certificate and run outside App Sandbox. Window restoration uses Accessibility access, enabled from Settings. Peekaboo does not request Input Monitoring access.

## Build and test

Requires macOS 26 and Xcode 26, with Xcode's developer directory selected. Check `xcode-select -p`: it should point inside Xcode, such as `/Applications/Xcode.app/Contents/Developer`, rather than the standalone Command Line Tools directory. Open Xcode once to complete its installation.

No Apple account, developer team, paid membership, or Homebrew packages are needed. After cloning the repository, run:

```sh
make install
open /Applications/Peekaboo.app
```

Before building or testing, Make checks for a usable signing identity named **Peekaboo Local Development**. If none exists, `scripts/setup-signing.sh` uses macOS's `openssl` and `security` tools to create a certificate and private key in your login Keychain, then trusts that certificate for code signing for your user. macOS may ask you to unlock Keychain or approve access during setup or signing. Run these commands as your normal user, without `sudo`.

Setup signs a temporary file before Xcode starts, so the first key-access approval finishes before parallel signing jobs begin. If macOS asks whether `codesign` can use the key, choose **Always Allow**. Denying access stops the build; rerun the command after resolving the prompt. If opening the project directly in Xcode, run `make certificate` once first.

Each Mac creates its own identity; Debug and Release reuse it on later builds. Keep the certificate and its private key in Keychain. They stay outside the repository, and cleaning the build directory doesn't remove them. If an existing certificate is unusable, setup stops with instructions instead of silently replacing the identity.

```sh
make certificate # Set up or check the certificate without building
make build   # Debug build
make app     # Signed Release app
make install # Install Release app in /Applications
make check   # Build and test
make run     # Open the Debug app
```

`make app` produces `.build/Build/Products/Release/Peekaboo.app` and verifies its signature. `make install` replaces `/Applications/Peekaboo.app`; use `make install PREFIX=/another/existing/directory` to install elsewhere. Quit and reopen Peekaboo to use a newly installed build.

`make check` runs the same build-and-test pass as `make test`. Both Swift and Clang treat compiler warnings as errors. These commands use the shared `Peekaboo` scheme, a macOS destination matching the host architecture, and `.build/` for derived data. After `make certificate`, the underlying commands on Apple silicon are:

```sh
xcodebuild -project Peekaboo.xcodeproj -scheme Peekaboo -destination 'platform=macOS,arch=arm64' -derivedDataPath .build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES -configuration Debug build
xcodebuild -project Peekaboo.xcodeproj -scheme Peekaboo -destination 'platform=macOS,arch=arm64' -derivedDataPath .build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES -configuration Debug test
```

Tests use temporary configuration files. The scheme sets `PEEKABOO_TESTING=1` in the test host so it does not restore your own assignments or register their shortcuts.

## Signing and Accessibility permission

Switching from an Apple Development or ad hoc build changes Peekaboo's signing identity and requires a new Accessibility grant. Quit Peekaboo, remove its old entry from **System Settings → Privacy & Security → Accessibility**, add `/Applications/Peekaboo.app`, enable it, then reopen the app. Replacing or losing the local signing certificate also requires granting access again.

Reusing the certificate keeps the signing identity stable across updates. An installed update signed with this local certificate retained its Accessibility grant without another approval; see [native checks](docs/native-checks.md) for recorded results. Apple explains how macOS recognizes updated code in [Inside Code Signing: Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

This setup supports building from source for your own Mac. It doesn't notarize the app or prepare it for the Mac App Store. Sharing the resulting binary doesn't make its certificate trusted on someone else's Mac; Gatekeeper may block it or require manual approval. Other users can clone the repository and build with their own local certificate.

## Assign an app

Open **Peekaboo → Settings…** from the menu bar, click **Add App…**, and choose an installed `.app`. Click its **Record shortcut** field, press a key with Command, Control, or Option, then release the key to save. Escape, the field's cancel icon, closing settings, or switching away from Peekaboo cancels recording. Peekaboo suspends its own shortcuts during recording and restores them afterward.

Selecting **Settings…** again brings the existing Settings window forward, even when another app is active.

Click an assignment's shortcut field to edit it. The field shows a focus outline while recording. A rejected replacement keeps the previous assignment. Errors appear in settings and the menu bar; a failed startup registration leaves the assignment visible for correction. Choosing the same shortcut again retries its registration.

Before saving, Peekaboo compares the recorded combination with enabled macOS Keyboard Shortcuts, even when the combination is unchanged. A match opens a native warning with **Cancel** and **Use Anyway**. Cancel keeps the previous assignment. Use Anyway saves using the existing registration when the shortcut is unchanged and still registered; otherwise it attempts native registration and saves only if that succeeds. If macOS shortcut inspection is unavailable, Peekaboo reports that the check failed and does not change the assignment. Record the shortcut again to retry the check.

Toggle errors appear with the affected assignment and clear after that assignment toggles successfully. You can also dismiss them. Settings actions and toggles for other assignments do not clear them, and successful toggles do not clear Settings errors. Removing an assignment or replacing its app removes its old toggle error.

The **trash button** removes the app–shortcut pairing and releases its global shortcut. If saving fails, the assignment stays usable. If macOS cannot release a deleted shortcut, Peekaboo reports the cleanup error; use **Reload Saved Assignments** to retry.

Assignments target the installed copy you selected, identified by its file URL and bundle identifier. If that copy moves or disappears, click the app's name or icon to select it again and record its shortcut. Peekaboo will not silently launch another installed copy. You can add more than one assignment; each shortcut must be unique within Peekaboo.

Configuration lives at `~/Library/Application Support/AppToggle/assignments.json`. The storage directory and bundle identifier (`com.nelsongoncalves.AppToggle`) retain the original name to preserve saved assignments and the app’s identity through the Peekaboo rename. Writes replace the file atomically. A failed read blocks saving to protect the existing file; correct the reported file problem and use **Reload Saved Assignments**. A failed write leaves the previous saved assignment intact.

## Native behavior and limits

Each completed shortcut gesture requests one app toggle. Peekaboo checks the app's current state for every gesture, including changes made outside Peekaboo, and suppresses repeated launch requests while one is outstanding.

Enable Peekaboo in **System Settings → Privacy & Security → Accessibility** using **Allow Accessibility…** in Peekaboo settings. Peekaboo tracks focused windows of assigned apps while it runs. It restores the most recently used window if that window is minimized, leaving other minimized windows alone. An active app with all its windows minimized is restored instead of hidden. Apps hidden with ⌘H are brought forward too.

An active app with no standard windows is hidden. While Accessibility access is denied, Peekaboo can still launch, hide, and activate apps; the menu bar keeps its warning icon and Settings shows permission guidance. Peekaboo rechecks permission when you switch apps, so after granting or revoking access, switch away from System Settings to update the menu icon. You do not need to reopen Peekaboo Settings. Other toggle or Settings errors keep their warnings until resolved or dismissed.

Window history starts when Accessibility access and tracking are available; it is not saved across restarts. If the app has only one window and no history exists, Peekaboo can identify that window. If several windows exist with no known recent window, it asks you to open the desired window once instead of guessing. Unsupported or unavailable window access produces an error, while ordinary app hiding and activation remain available.

If a focus update fails, Peekaboo keeps the last recorded window order. A missed focus change can therefore cause it to restore an older window until it observes focus again.

Activation requests bring non-minimized windows forward. Peekaboo does not change window positions or move windows between Spaces; macOS controls Space switching. A successful native request is not a guarantee of immediate focus. Peekaboo reports rejected restoration and activation requests.

Shortcut labels reflect the keyboard layout used during recording. Command, Control, Option, and Shift flags are normalized; the label includes recognizable names or glyphs for special keys. Shortcuts use physical key codes, so re-record them if you change layouts and want a different physical combination.

Peekaboo rejects duplicate shortcuts within its own assignments. **Use Anyway** applies only to a known macOS system shortcut and cannot bypass that rule. The conflict check covers enabled shortcuts reported by macOS, not application-specific shortcuts or every way a combination can be intercepted. A successful registration does not prove that macOS or another app will deliver the combination to Peekaboo.

See [native checks](docs/native-checks.md) for interactive steps and recorded results. Passing automated tests does not establish physical global shortcut delivery, window behavior, or Space switching.
