# Contributing to Peekaboo

Thanks for your interest in improving Peekaboo.

## Reporting bugs and ideas

Open a [GitHub issue](https://github.com/goncalvesnelson/Peekaboo/issues). For bugs, include:

- your macOS version and keyboard layout
- the shortcut and target app involved
- what you expected and what happened
- any error text from Settings or the menu bar

## Making changes

1. Build and test with `make check`. It must pass with no warnings, because warnings are treated as errors.
2. Keep to Apple frameworks. Peekaboo has no third-party dependencies.
3. Add or update flow-level tests in `PeekabooTests/` for any behavior change.
4. Update the README and [native checks](docs/native-checks.md) when behavior changes, and record which interactive checks you ran.

Read [native macOS API research](docs/research/native-macos-apis.md) before changing shortcut registration, conflict detection, or app activation. Domain terms such as *assignment*, *app toggle*, and *system shortcut conflict* are defined in [CONTEXT.md](CONTEXT.md).

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
