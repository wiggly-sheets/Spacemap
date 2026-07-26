# Spacemap

<div align="center">

<img width="512" height="512" alt="icon_256x256@2x" src="https://github.com/user-attachments/assets/ca74882b-0ffb-49d9-b579-f4ee0840969b" />

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

## Features

- **2D Grid Visualization** — See all your spaces laid out in rows and columns
- **Live Updates** — Active cell updates instantly via yabai's `space_changed` signal
- **Three Cell Styles** — Colored rectangles, app icons, or live thumbnails
- **Keyboard Navigation** — Arrow keys and Vim keys (hjkl) to navigate the grid
- **Drag & Drop** — Drag windows directly onto cells to move them to that space
- **Customizable** — Themes, grid size, transparency, hotkeys, and more
- **Auto-Updates** — Built-in Sparkle updates with configurable behavior

## Quick Start

### 1. Install a supported window manager

```bash
brew install asmvik/formulae/yabai
```

Spacemap also supports [AeroSpace](https://github.com/nikitabobko/AeroSpace):

```bash
brew install --cask nikitabobko/tap/aerospace
```

Spacemap automatically prefers yabai when both are running. `skhd` is optional for external shortcuts:

```bash
brew install koekeishiya/formulae/skhd
# or: brew install jackielii/formulae/skhd-zig
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

Upgrade with homebrew using:
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

Config file: `~/.config/spacemap/spacemap.jsonc`

Most changes take effect on next HUD open. Hotkey changes are applied immediately when saved in Settings.
Spacemap reads legacy `key=value` configs, but new installs and resaves use JSON. JSONC line and block comments are accepted. Missing or invalid fields are repaired individually, with the original saved as `spacemap.jsonc.bak`.

The option tables below use the uppercase legacy aliases for easy comparison with older configs. New JSON/JSONC files use camel-case field names and are best edited through Settings.

### Display

| Option | Default | Description |
|--------|---------|-------------|
| `CELL_STYLE` | `rects` | `rects`, `icons`, or `thumbnails` |
| `THEME` | `default` | Theme name from `~/.config/spacemap/themes/` |
| `UI_SCALE` | `0.5` | HUD size (0.5×–4.0×) |
| `BACKGROUND_ALPHA` | `0.3` | HUD transparency (0–1) |
| `MODE` | `auto` | `dark`, `light`, or `auto` |
| `ICON_SCALE` | `0.5` | App icon size (0.2×–1.0×) |
| `SHOW_ICON_STRIP` | `true` | Show icons at cell bottom |
| `SHOW_SPACE_NUMBERS` | `true` | Show space numbers |
| `SHOW_SPACE_NAMES` | `true` | Show custom names in cells |
| `HIDE_MENUBAR_ICON` | `false` | Run headless |

### Grid

| Option | Default | Description |
|--------|---------|-------------|
| `GRID_COLS` | `8` | Number of columns |
| `GRID_ROWS` | `2` | Number of rows |
| `MULTI_MONITOR_HUD_MODE` | `unified` | `unified` combines spaces in one grid; `separate` shows one grid per display |
| `UNIFIED_HUD_VISIBILITY` | `active` | In `unified` mode: `active` shows the grid on the focused-space display; `all` shows it on every display |
| `SEPARATE_HUD_VISIBILITY` | `all` | In `separate` mode: `all` shows every HUD; `active` shows only the focused-space display |
| `DISPLAY_NAVIGATION_WRAP` | `within` | With arrow/Vim navigation: `within` stays on one display; `between` wraps across displays |
| `MAX_SPACES` | `16` | Maximum spaces to display |

### Navigation

| Option | Default | Description |
|--------|---------|-------------|
| `ARROW_KEYS` | `false` | Enable arrow key navigation |
| `VIM_KEYS` | `false` | Enable hjkl navigation |
| `DISPLAY_NAVIGATION_WRAP` | `within` | Wrap keyboard navigation within or between displays |

### Behavior

| Option | Default | Description |
|--------|---------|-------------|
| `AUTO_HIDE_TIMEOUT` | `5` | Seconds before auto-hide (0=never) |
| `PINNED_HOTKEY` | `none` | Optional shortcut that toggles a HUD with no auto-hide timer |
| `FOCUS_SPACE_ON_WINDOW_DROP` | `false` | Focus the destination after dropping a window |
| `UPDATE_MODE` | `notify` | `auto`, `notify`, or `off` |

### Hotkey

```jsonc
{
  "hotkey": {
    "keyKind": "keyCode",
    "keyCode": 49,
    "modifiers": ["ctrl"]
  },
  "pinnedHotkey": {
    "keyKind": "none",
    "modifiers": []
  }
}
```

The Settings hotkey recorders are recommended for editing these values. The pinned shortcut must differ from the normal shortcut. Using the normal shortcut while pinned hides the HUD and returns it to normal timed behavior on its next use.

### Space Names

```jsonc
{
  "spaceNames": {
    "1": "Desktop",
    "2": "Dev",
    "3": "Media",
    "4": "Music"
  }
}
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
spacemap --settings   # open settings
spacemap --config     # edit config file
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
- [skhd](https://github.com/koekeishiya/skhd)
- [aerospace](https://github.com/nikitabobko/AeroSpace)
