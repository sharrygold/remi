# Perch

A floating command centre for macOS: tasks, notes and links, one click or one shortcut away. Everything stays on your Mac.

"Perch" is a working name. The name shown in the app comes from `APP_DISPLAY_NAME` in `project.yml`; change it there and reinstall to rename. Your data and settings are kept, because they follow the bundle ID (`com.example.oldapp`), not the name.

## Install

You need Xcode and XcodeGen (`brew install xcodegen`). Then, in Terminal:

```
cd ~/projects/Perch
Scripts/install.sh
```

The script builds a Release copy, closes any running one, puts it in `/Applications` and opens it. Run it again whenever you want the latest version. Afterwards, turn on **Settings > General > Open at login**.

The first time, macOS asks whether the app may send notifications; choose **Allow**. If you use a Focus mode, add the app under **System Settings > Focus > (your Focus) > Allowed Notifications > Apps**, or reminders stay silent during that Focus.

## Build and run without installing

```
xcodegen generate
xcodebuild -project Perch.xcodeproj -scheme Perch -derivedDataPath build build
open build/Build/Products/Debug/Perch.app
xcodebuild -project Perch.xcodeproj -scheme Perch -derivedDataPath build test   # unit tests
```

The `.xcodeproj` is generated from `project.yml`; don't edit it by hand.

## Using it

Open the panel by clicking the widget, pulling the cord, or pressing **⌃Space** (change it in Settings).

| In the capture bar | |
|---|---|
| Return | Save as a task |
| ⌘Return | Save as a note |
| A pasted link, then Return | Save to Saved links, or Watch later for videos |
| Tab (on a link) | Switch between Saved links and Watch later |
| Text plus a link | A task that opens that link |
| `#space`, `today`, `tomorrow`, `fri`, `!` | Space, due date, important |
| ⌘Z (capture bar empty) | Undo the last change |

| Anywhere in the panel | |
|---|---|
| ↓ then ↑ ↓ | Move through the list |
| Return | Open a note or link, edit a task's title |
| Space | Tick a task, mark a video watched |
| ⌘O | Run a task's action |
| ⌘P | Pin a note or link, mark a task important |
| ⌘R | Rename a link or task (or right-click > Rename). Esc cancels |
| ⌘⌫ | Delete (goes to Recently Deleted for 30 days) |
| ⇧⌘[ and ⇧⌘] | Move the selected item to the previous or next Space |
| ⌘1–4 | Today, Tasks, Notes, Links |
| ⌘[ and ⌘] | Previous or next Space |
| ⌘F | Search everything |
| ⌘N | New note |
| ⌘, | Settings |
| Esc | Step back: list, search, then close |

In a note: `# ` heading, `- ` bullet, `[] ` checkbox, `**bold**` (or ⌘B), ⇧⌘L checklist line, ⇧⌘U tick, Esc back to the list. Drag the panel's edges to resize it.

## Where things are kept

- Library: `~/Library/Application Support/com.example.oldapp/Library.store`
- Daily backups (last 14): the `Backups` folder next to it, also reachable from **Settings > Data > Show in Finder**
- Export writes JSON (which Import reads back) and a Markdown copy.

Nothing is sent anywhere except the page fetch that gets a saved link's title and icon.

## Project layout

- `App/Core`: models, store, parser, search, export, backups. No UI; this is what the unit tests compile, and what a future iPhone app could reuse.
- `App`: the app around the core. `AppController.swift` starts everything (menus, settings, daily jobs), with extensions for the panel (`+Panel`), the widget (`+Widget`), the Settings window (`+Settings`) and the self-tests and demo data (`+SelfTests`). `main.swift` is just the entry point and launch options; `Windows.swift` holds the window classes. The SwiftUI views are in `PanelView`, `NotesPane`, `LinksPane`, `SearchPane`, `SettingsView` and `WidgetPrototypes`. `DesignTokens.swift` holds the whole look.
- `Tests`: unit tests. `Scripts`: install and screenshot scripts.
- `SPEC.md` is the product spec, `DECISIONS.md` records what changed and why, `PROGRESS.md` tracks milestones, `QA.md` is the acceptance checklist.

The app also has in-app self-tests used during development (`--m2-selftest` to `--m6-selftest`, `--clipboard-selftest`, `--cord-selftest`). They run on in-memory data and press real keys in the panel, so don't type while one runs.
