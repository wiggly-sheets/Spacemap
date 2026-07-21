# spacemap FAQ

## General

### What is spacemap?
A native macOS utility that shows a floating 2D grid overlay of your yabai workspaces. Think of it as "mission control" for tiling window managers — no SIP disable needed.

### Do I need to disable SIP?
No. spacemap uses CGEventTap and Accessibility API, not SIP-disabling kernel extensions.

## Installation

### Can I install spacemap without Homebrew?
Yes, download the DMG from [releases](https://github.com/jsheffie/spacemap/releases), open it, and drag `spacemap.app` to Applications. Or build from source with `make run`.

### Why does spacemap need Accessibility permission?
It uses CGEventTap to detect the toggle hotkey. Permission is prompted on first launch.

### After rebuilding, why did my hotkey stop working?
Every rebuild changes the binary hash, revoking Accessibility permission. Use `make dev1` → remove from System Settings → `make dev2`.

## Configuration

### Where is the config file?
`~/.config/spacemap/config`

### Does editing config require restart?
Most keys reload when HUD re-opens. Only `HOTKEY` requires app restart.

### Can I use inline comments in config?
Yes: `KEY=VALUE # comment` works. The parser strips everything after `#`.

### Can I customize space names?
Yes. Add `SPACE_NAMES=1:Desktop,2:Dev,3:Media` to config. Numbers shown top-right, names in cell center. Also editable via Settings window.

### Can I change the hotkey?
Set `HOTKEY=ctrl+shift+s` in config. Requires restart. Supported modifiers: `ctrl`, `cmd`, `alt`, `shift`. Supported keys: `pgdn`, `pgup`, `space`, `tab`, `return`, `escape`, `home`, `end`, `left`, `right`, `up`, `down`, `f1`–`f12`, letters, digits.

## Usage

### How do I open/close the HUD?
Press the configured hotkey (default: `Ctrl+PgDn`). Or click the menubar icon → Show/Hide Spacemap.

### How do I switch to a workspace?
Click on any cell in the HUD. The HUD closes and yabai switches to that space.

### How do I move a window to another space?
Drag the window from its current position onto a HUD cell. The window moves to that space.

### Why does the HUD auto-hide?
By default it hides 5 seconds after the last space change. Set `AUTO_HIDE_TIMEOUT=0` to disable auto-hide.

### How do I open settings?
Menubar → Settings, or press `⌘,`, or run `spacemap --settings`.

### Can I auto-start spacemap on login?
Yes. Click the menubar icon → Launch at Login.

## Development

### How do I build from source?
`make run` (build, install, launch). Or `make build` for just the binary, `make app` for the .app bundle.

### How do I test changes?
`make dev1` (uninstall) → remove Accessibility permission → code changes → `make dev2` (rebuild, install, launch) → grant permission. Run unit tests with `make test`.

### How do I run unit tests?
`make test` or `swift test`. 103 tests across 5 files (hotkey parsing, config, themes, models, grid computation).

### Why can't I run the binary directly?
macOS grants Accessibility to the `.app` bundle, not the raw binary. Running it directly fails the trust check.

### How do I view logs?
Open Console.app, filter by process "spacemap" or subsystem "spacemap".

### How do I send a test signal to the HUD?
```bash
yabai -m signal --add label=test event=space_changed action="echo 'test' | nc -U /tmp/spacemap_$(whoami).socket"
```
Or connect to the socket and send `0` (refresh), `1` (show), `2` (hide).

## Troubleshooting

### HUD doesn't appear on hotkey
1. Verify Accessibility permission is granted (System Settings → Privacy & Security → Accessibility)
2. Check Console.app for "permission not granted" logs
3. Restart the app

### yabai not found error
yabai is auto-detected at `/opt/homebrew/bin/yabai` (ARM) or `/usr/local/bin/yabai` (Intel). Ensure yabai is installed: `which yabai`.

### Config not taking effect
Most config keys reload on HUD open. Close and re-open the HUD (`Ctrl+Space` twice). If it's `HOTKEY`, restart the app.

### Space names not showing
Verify `SPACE_NAMES` format: `SPACE_NAMES=1:Desktop,2:Dev,3:Media` (comma-separated, no spaces around `:`).

### App won't launch
Check Console.app for crash logs. Ensure yabai is running (the app checks on launch and shows an alert if not). Reinstall with `make dev1` → `make dev2`.

## Known Limitations

- **Homebrew only:** No other package managers supported.
- **Icon flicker:** Icons re-fetched on every render; IconCache mitigates.
- **Drag ambiguity:** Multi-window app drags may fall back to click proximity.