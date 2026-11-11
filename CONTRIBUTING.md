# Contributing to Remi

Thank you for wanting to help. Remi is small on purpose, so the best changes keep it calm, fast and private.

## Build and run

You need Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Remi.xcodeproj -scheme Remi -derivedDataPath build/debug build
open build/debug/Build/Products/Debug/Remi.app
```

`Scripts/b.sh` does the same quiet Debug build in one step. Debug builds keep their own data folder, so they never touch your real library.

Add `--demo-data` to run on sample content kept in memory. Nothing is saved.

## Tests

```sh
xcodebuild -project Remi.xcodeproj -scheme Remi -derivedDataPath build/debug test
```

The unit tests cover `App/Core`: the capture parser, the store, search, repeats, export and backups.

### Self-tests

Some behaviour can only be checked in the running app, so Remi has self-tests that press real keys in a real panel and print what happened. They take the keyboard while they run, so leave the Mac alone for a minute or two.

```sh
BIN=build/debug/Build/Products/Debug/Remi.app/Contents/MacOS/Remi
$BIN --m2-selftest        # capture bar: Return, tokens, undo
$BIN --m3-selftest        # notes: Markdown shortcuts, checkboxes
$BIN --m4-selftest        # links: titles, Watch later, duplicates
$BIN --m5-selftest        # search, Settings, shortcuts
$BIN --m6-selftest        # moving around with the keyboard
$BIN --clipboard-selftest # the copied-link chip
$BIN --add-selftest       # the New task and Add link buttons
```

## Screenshots

`Scripts/shot.sh` and `Scripts/window-shot.sh` take screenshots on demo data without taking the keyboard. macOS asks for Screen Recording permission the first time.

## What's welcome

- Bug fixes, with the steps that show the bug.
- Small improvements to capture, search, the keyboard and accessibility.
- Support for another browser in ⌃⌥S.

Please open an issue before starting anything large, so we can agree on it first. Remi will stay local: changes that add accounts, syncing through a server, analytics or tracking won't be merged.

## Style

- Swift, SwiftUI and AppKit, no third-party dependencies.
- `App/Core` has no UI, so it stays testable.
- The `.xcodeproj` is generated from `project.yml`. Edit `project.yml`, never the project file.
- Words in the app are calm, warm and plain. Be kind about undone things: no streaks, no guilt.
