# HandoffWatcher

A native macOS utility for monitoring and restarting the local services used by Universal Clipboard.

HandoffWatcher checks `pboard`, `sharingd`, and `useractivityd`, displays their status in the menu bar and app window, and provides a manual restart action. The interface supports English and Simplified Chinese, following macOS language preferences.

**A healthy status does not guarantee that copying between devices works.** HandoffWatcher checks local service state, not end-to-end connectivity. It does not read, store, or transmit clipboard contents.

## Requirements

- macOS 27 or later on Apple Silicon
- Swift command-line tools with the macOS 27 SDK to build
- Python 3 to run tests

## Build and Run

From the project directory:

```sh
./build.sh
open outputs/HandoffWatcher.app
```

The build produces `outputs/HandoffWatcher.app` and `outputs/HandoffWatcher-macOS27-arm64.zip`. You can move the app to `/Applications`.

Builds use ad-hoc signing and are not notarized.

## Usage

- **Restart Services** restarts the current user's clipboard and Handoff services without administrator privileges. Restarting may clear the clipboard.
- Close the window to keep monitoring in the menu bar. Click the Dock icon to reopen it.
- Choose **Quit** or press **⌘Q** to exit.

Checks run every three seconds and after wake. Services that are idle until needed are treated as healthy. HandoffWatcher does not restart services automatically.

To change the app language, use **System Settings → General → Language & Region → Applications**, then restart the app. English is the fallback when no supported language matches.

## Command Line

Inspect service status without restarting services:

```sh
./outputs/HandoffWatcher.app/Contents/MacOS/HandoffWatcher --diagnose
```

Add `--verbose` to include raw error diagnostics. Use `--restart-services` instead of `--diagnose` to restart services and report the result.

Commands return JSON and exit with a nonzero status if a service check or restart fails. Field names remain stable; `detail` and `error` follow the app language.

## Tests

```sh
./build.sh
./test.sh
```

Tests cover service status parsing, simulated restart outcomes, localization, time formatting, and packaged resources. They do not restart system services.
