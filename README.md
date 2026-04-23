# Clipboard Typer

A small macOS utility for recording demos. It queues text from the clipboard and types the next queued message into the currently focused app with natural delays.

## Shortcuts

- `Ctrl-Opt-Cmd-C`: enqueue the current clipboard text.
- `Ctrl-Opt-Cmd-V`: type the next queued message.
- `Ctrl-Opt-Cmd-O`: open the controls window.

The Dock app opens a native glassy controls window where you can type manually, stop the current typing task, clear the queue, grant Accessibility permission, or change the typing speed with a `100-300` WPM slider. The default speed is `160` WPM.

The app also keeps a small menu bar item when macOS has room for it. If macOS hides that item, run this from the project folder to bring the controls window forward:

```bash
open ".build/Clipboard Typer.app"
```

## Run locally

```bash
swift run
```

The app runs as a normal macOS Dock app. On first typing attempt, macOS will ask for Accessibility permission because synthesized keyboard events require it. If the prompt does not appear, use the controls window's `Grant Accessibility` button.

## Build

```bash
swift build -c release
```

The compiled executable will be at `.build/release/ClipboardQueueMenuBar`.

To create a local app bundle:

```bash
Scripts/build-app.sh
open ".build/Clipboard Typer.app"
```

## Notes

- Clipboard entries are kept in memory only.
- Consecutive duplicate clipboard entries are ignored to prevent accidental double-enqueue.
- Stopping a typing task cancels the current message and keeps the rest of the queue intact.
- The typing speed slider is saved in `UserDefaults`.
