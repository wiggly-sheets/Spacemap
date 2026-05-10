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

### 1. Install prerequisites

```bash
brew install asmvik/formulae/yabai
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


Or download a DMG from the [releases page](https://github.com/wiggly-sheets/spacemap/releases).

> **macOS quarantine:** If the app won't open after download, run:
> ```bash
> xattr -d com.apple.quarantine /Applications/spacemap.app
> ```

### 3. Grant Accessibility permission

Launch Spacemap once (`open /Applications/spacemap.app`), then enable it in **System Settings → Privacy & Security → Accessibility**.

### 4. Configure Spacemap

```bash
mkdir -p ~/.config/spacemap
cat > ~/.config/spacemap/config << 'EOF'
GRID_COLS=8
GRID_ROWS=2
CELL_STYLE=icons
EOF
```

Press `Ctrl+Space` to open Spacemap.

---

### Cell styles

`CELL_STYLE` controls how windows are drawn inside each cell:

| Value | Description |
|-------|-------------|
| `rects` | Colored rectangles scaled from real window geometry (default) |
| `icons` | App icons positioned at each window's scaled location |

```bash
CELL_STYLE=rects   # default
CELL_STYLE=icons
```

**`CELL_STYLE=rects`**

<img width="752" height="476" alt="rects style" src="https://github.com/user-attachments/assets/1ee3e85c-12e4-4f34-a265-cb9f9fd69b56" />

**`CELL_STYLE=icons`**

<img width="718" height="464" alt="icons style" src="https://github.com/user-attachments/assets/5d35aa23-d5ef-4da1-8a74-df7278b43112" />

Run `make distconfig` to write a fresh config with `icons` active and `rects` commented out.

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

## Configuration

Config file: `~/.config/spacemap/config`

Most changes take effect on next HUD open. `HOTKEY` requires a restart.

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
| `MAX_SPACES` | `16` | Maximum spaces to display |

### Navigation

| Option | Default | Description |
|--------|---------|-------------|
| `ARROW_KEYS` | `false` | Enable arrow key navigation |
| `VIM_KEYS` | `false` | Enable hjkl navigation |

### Behavior

| Option | Default | Description |
|--------|---------|-------------|
| `AUTO_HIDE_TIMEOUT` | `5` | Seconds before auto-hide (0=never) |
| `UPDATE_MODE` | `notify` | `auto`, `notify`, or `off` |

### Hotkey

```bash
HOTKEY=ctrl+space    # default
#HOTKEY=ctrl+alt+s
```

Format: `modifier+modifier+key`

### Space Names

```bash
SPACE_NAMES=1:Desktop,2:Dev,3:Media,4:Music
```

---

## Requirements

- macOS 13+ (macOS 14+ for thumbnails)
- [yabai](https://github.com/koekeishiya/yabai) running
- [skhd](https://github.com/koekeishiya/skhd) running
- Accessibility permission
- Screen Recording permission (thumbnails only)

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
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Contributing guidelines |

---

## Inspired By

- [WindowMaker](https://www.windowmaker.org/)
- [yabai](https://github.com/koekeishiya/yabai)
- [YabaiGridSpaces](https://codeberg.org/mikkelricky/hammerspoon/src/branch/main/Spoons/YabaiGridSpaces.spoon)
- [skhd](https://github.com/koekeishiya/skhd)
- [aerospace](https://github.com/nikitabobko/AeroSpace)
