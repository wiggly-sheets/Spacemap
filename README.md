# Spacemap

<div align="center">

<img width="256" height="256" alt="icon_128x128@2x" src="https://github.com/user-attachments/assets/461e8c96-ce0c-4198-927a-66c32d991abb" />

![Release](https://github.com/wiggly-sheets/Spacemap/actions/workflows/release.yml/badge.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2013+-lightgrey)
![Swift](https://img.shields.io/badge/swift-5.9-orange)

**A native macOS utility that visualizes your yabai workspaces as a 2D grid overlay.**

Press `Ctrl+Space` to toggle a floating HUD showing all your desktops as a grid with window positions highlighted inside each cell.

</div>

---

## About

Spacemap gives you a visual reference for your yabai workspace layout. With [yabai](https://github.com/koekeishiya/yabai) and [skhd](https://github.com/koekeishiya/skhd) / [skhd.zig](https://github.com/jackielii/skhd.zig), you can arrange your desktop switching on a grid—but you have no visual confirmation of where things are until you're already there.

Spacemap solves this. It renders your spaces as a 2D grid, updating in real-time as you switch between them.

> No SIP disabling required. This is a standard macOS app that runs alongside yabai without any kernel modifications.

<img width="1610" height="984" alt="56203" src="https://github.com/user-attachments/assets/1b28a8ca-b6a8-4b69-869e-cf405a643cea" />

## Features

- **2D Grid Visualization** — See all your spaces laid out in rows and columns
- **Live Updates** — Active cell updates instantly via yabai's `space_changed` signal
- **Five Cell Styles** — Rectangles, Hybrid rectangles with app icons, geometry-aware app icons, live thumbnails, or simple cells
- **Keyboard Navigation** — Arrow keys and Vim keys (hjkl) to navigate the grid
- **Drag & Drop** — Drag windows directly onto cells to move them to that space
- **Customizable** — Themes, grid size, transparency, hotkeys, and more
- **Auto-Updates** — Built-in Sparkle updates with configurable behavior

## Quick Start

### 1. Install prerequisites

```bash
brew install asmvik/formulae/yabai
```

### 2. Install Spacemap
Install spacemap via Homebrew:

```bash
brew tap wiggly-sheets/spacemap https://github.com/wiggly-sheets/homebrew-spacemap.git
brew install --cask spacemap
```

Or in one step:

```bash
brew install wiggly-sheets/spacemap/spacemap
```

Upgrade with Homebrew using:
```bash
brew update && brew upgrade wiggly-sheets/spacemap/spacemap
```


Or download a DMG from the [releases page](https://github.com/wiggly-sheets/spacemap/releases).

> **macOS quarantine:** If the app won't open after download, run:
> ```bash
> xattr -d com.apple.quarantine /Applications/spacemap.app
> ```

### 3. Grant Accessibility permission

Launch Spacemap once (`open /Applications/spacemap.app`), then enable it in **System Settings → Privacy & Security → Accessibility**.

### 4. Open Spacemap

Press `Ctrl+Space` to open Spacemap.

---

## Usage

| Action | Result |
|--------|--------|
| `Ctrl+Space` | Toggle HUD |
| Arrow keys / hjkl | Navigate spaces in grid |
| `Escape` | Close HUD |
| `Return` | Jump to selected space |
| Click on cell | Switch to that space |
| `⌘+,` while HUD is up or menu bar is open| Open Settings |
| `⌘+R` while menu bar is open | Restart Spacemap |

### Deep links

| URL | Result |
|-----|--------|
| `spacemap://toggle-hud` | Toggle HUD |
| `spacemap://pin-hud` | Show and pin HUD |
| `spacemap://settings` | Open Settings |
| `spacemap://menu` | Open the menu-bar menu |
| `spacemap://config` | Open the config file |
| `spacemap://themes` | Open the themes folder |

---

## Settings

Open Settings from the menu bar or press `⌘+,` while the HUD is visible. The sidebar is always shown, highlights the active category, and opens each category in its own detail view:

| Category | Controls |
|----------|----------|
| **Grid** | Space limit and layout, display modes, cell style, space numbers, icon strip, and extra windows |
| **Space Names** | Space-name visibility and per-space names |
| **Appearance** | Theme, light/dark mode, transparency, icon scale, and UI scale |
| **Behavior** | Normal and pinned HUD hotkeys, HUD position, auto-hide, keyboard navigation, window-drop focus, menu bar visibility, and updates |
| **Debug/Advanced** | Socket health interval |

Changes save automatically. The hotkey recorder supports regular keys, F13–F20, and media keys; use its clear button to disable the binding.

---

## Configuration

Config file: `~/.config/spacemap/config.toml`

Most changes take effect on next HUD open. Hotkey changes are applied immediately when saved in Settings.
Spacemap accepts TOML only. Missing or invalid fields are repaired individually, with the original saved as `config.toml.bak`.

TOML tables mirror the Settings categories: `[grid]`, `[spaceNames]`, `[appearance]`, `[behavior]`, and `[advanced]`. Hotkeys and HUD position use nested tables under `[behavior]`. The option tables below use TOML’s camel-case field names.

### Display

| Option | Default | Description |
|--------|---------|-------------|
| `cellStyle` | `rects` | `rects`, `hybrid`, `icons`, `thumbnails`, or `simple` |
| `theme` | `default` | Theme name from `~/.config/spacemap/themes/` |
| `uiScale` | `0.5` | HUD size (0.5×–4.0×) |
| `backgroundAlpha` | `0.3` | HUD transparency (0–1) |
| `mode` | `auto` | `dark`, `light`, or `auto` |
| `iconScale` | `0.5` | App icon size (0.2×–1.0×) |
| `showIconStrip` | `true` | Show icons at cell bottom |
| `showSpaceNumbers` | `true` | Show space numbers |
| `showSpaceNames` | `true` | Show custom names in cells |
| `hideMenuBarIcon` | `false` | Run headless |

### Grid

| Option | Default | Description |
|--------|---------|-------------|
| `cols` | `8` | Number of columns |
| `rows` | `2` | Number of rows |
| `multiMonitorHUDMode` | `unified` | `unified` combines spaces in one grid; `separate` shows one grid per display |
| `unifiedHUDVisibility` | `active` | In `unified` mode: `active` shows the grid on the focused-space display; `all` shows it on every display |
| `separateHUDVisibility` | `all` | In `separate` mode: `all` shows every HUD; `active` shows only the focused-space display |
| `displayNavigationWrap` | `within` | With arrow/Vim navigation: `within` stays on one display; `between` wraps across displays |
| `maxSpaces` | `16` | Maximum spaces to display |

### Navigation

| Option | Default | Description |
|--------|---------|-------------|
| `useArrowKeys` | `false` | Enable arrow key navigation |
| `useVimKeys` | `false` | Enable hjkl navigation |
| `displayNavigationWrap` | `within` | Wrap keyboard navigation within or between displays |

### Behavior

| Option | Default | Description |
|--------|---------|-------------|
| `autoHideTimeout` | `5` | Seconds before auto-hide (0=never) |
| `pinnedHotkey` | `none` | Optional shortcut that toggles a HUD with no auto-hide timer |
| `focusSpaceOnWindowDrop` | `false` | Focus the destination after dropping a window |
| `updateMode` | `notify` | `auto`, `notify`, or `off` |

### Hotkey

```toml
[behavior.hotkey]
keyKind = "keyCode"
keyCode = 49
modifiers = ["ctrl"]

[behavior.pinnedHotkey]
keyKind = "none"
modifiers = []
```

The Settings hotkey recorders are recommended for editing these values. The pinned shortcut must differ from the normal shortcut. Using the normal shortcut while pinned hides the HUD and returns it to normal timed behavior on its next use.

### Space Names

```toml
[spaceNames.names]
"1" = "Desktop"
"2" = "Dev"
"3" = "Media"
"4" = "Music"
```

---

## Requirements

- macOS 13+ (macOS 14+ for thumbnails)
- [yabai](https://github.com/koekeishiya/yabai) running
- [skhd](https://github.com/koekeishiya/skhd) running
- Accessibility permission
- Screen Recording permission (thumbnails only)
- For multi-monitor HUD modes: **Displays have separate Spaces** enabled in System Settings → Desktop & Dock → Mission Control (log out and back in after changing it)

---

## Building

```bash
make run              # build, install, and launch
make test             # run unit tests
make dmg              # build DMG package
```

Xcode project:
```bash
python3 scripts/generate-xcodeproj.py
open spacemap.xcodeproj
```

Architecture-specific builds:
```bash
make app-arm64        # Apple Silicon
make app-x86_64       # Intel
make app-universal    # Both
```

---

## CLI

```bash
spacemap --version    # print version
spacemap --trigger    # toggle HUD
spacemap --space next # focus the next yabai space and show the HUD
spacemap --space 4    # focus space 4 and show the HUD
spacemap --space web  # focus a yabai space label and show the HUD
spacemap --settings   # open settings
spacemap --config     # edit config file
```

`--space` accepts indices 1–16, `prev`, `next`, `first`, `last`, `recent`,
`mouse`, or a yabai space label. This is useful in skhd bindings when the HUD
should appear only for explicit navigation:

```bash
ctrl - right : spacemap --space next
ctrl - left  : spacemap --space prev
```

Install the CLI:
```bash
make install-cli
```

When the app is launched from `/Applications`, it also installs the `spacemap`
command automatically. If macOS protects `/usr/local/bin`, Spacemap asks for
administrator approval to create that symlink; it never replaces an unrelated
item already at that path.

---

## Developer Notes

**Accessibility permission** is granted to the `.app` bundle, not the binary. Running the binary directly won't work.

**Permission is revoked on reinstall** because the binary hash changes. Use the dev workflow:

```bash
make dev1   # uninstall, then remove from System Settings → Accessibility
make dev2   # reinstall and re-grant permission
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| HUD doesn't appear | Check Accessibility permission |
| Config not applying | Close and reopen HUD |
| yabai not found | Ensure yabai is installed at `/opt/homebrew/bin/yabai` |
| Space names not showing | Format: `SPACE_NAMES=1:Name,2:Name` (no spaces around `:`) |
| App won't launch | Check Console.app for logs; run `make dev1` then `make dev2` |

To view logs: Open **Console.app**, filter by "spacemap".

---

## Documentation

| File | Purpose |
|------|---------|
| [AGENTS.md](./AGENTS.md) | Architecture and development workflow |
| [DEVELOPER.md](./DEVELOPER.md) | Technical deep-dive |
| [REFERENCE.md](./REFERENCE.md) | Config keys and API reference |
| [TASKS.md](./TASKS.md) | Roadmap and known issues |
| [SUPPORT.md](./SUPPORT.md) | Getting help and reporting issues |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Contributing guidelines |

---

## Inspired By

- [WindowMaker](https://www.windowmaker.org/)
- [yabai](https://github.com/koekeishiya/yabai)
- [YabaiGridSpaces](https://codeberg.org/mikkelricky/hammerspoon/src/branch/main/Spoons/YabaiGridSpaces.spoon)
- [skhd](https://github.com/koekeishiya/skhd) / [skhd.zig](https://github.com/jackielii/skhd.zig)
- [aerospace](https://github.com/nikitabobko/AeroSpace)
