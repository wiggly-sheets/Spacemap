<div align="center">

  <img src="Assets/AppIcon/LegacyAppIcon.png" width="128" alt="Spacemap app icon" />

  <h1>Spacemap</h1>

  <p><b>See your spaces. Move through them.</b></p>

  <p>
    A native macOS workspace map for yabai.<br/>
    Open a floating grid, see what lives where, and go straight there.
  </p>

  <p>
    <a href="https://github.com/wiggly-sheets/Spacemap/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/wiggly-sheets/Spacemap/ci.yml?branch=main&label=build" alt="Build status" /></a>
    <a href="https://github.com/wiggly-sheets/Spacemap/releases/latest"><img src="https://img.shields.io/github/v/release/wiggly-sheets/Spacemap?label=latest&color=red" alt="Latest release" /></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/wiggly-sheets/Spacemap?color=blue" alt="MIT License" /></a>
    <a href="https://github.com/wiggly-sheets/Spacemap"><img src="https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey" alt="macOS 13 or later" /></a>
    <a href="https://swift.org"><img src="https://img.shields.io/badge/swift-5.9-orange" alt="Swift 5.9" /></a>
  </p>

  <p>
    <a href="https://github.com/wiggly-sheets/Spacemap/releases/latest"><b>Download</b></a>
    &nbsp;·&nbsp;
    <a href="#installation">Install guide</a>
    &nbsp;·&nbsp;
    <a href="#using-spacemap">Use it</a>
    &nbsp;·&nbsp;
    <a href="#configuration">Configure it</a>
    &nbsp;·&nbsp;
    <a href="#build-from-source">Build from source</a>
  </p>

  <img width="900" alt="Spacemap HUD showing a grid of macOS spaces" src="https://github.com/user-attachments/assets/1b28a8ca-b6a8-4b69-869e-cf405a643cea" />

</div>

---

yabai makes moving around a workspace grid fast. Spacemap makes it legible: press one shortcut to see every space, its windows, and the space you are on—then jump, navigate, or drag a window exactly where it belongs.

> [!NOTE]
> Spacemap runs as a normal macOS app alongside yabai. It does not require disabling SIP or modifying macOS.

---

## Features

### A live map of your workspaces

- **2D grid HUD** — see spaces as a configurable rows-by-columns map
- **Live focus updates** — active space changes immediately through yabai signals
- **Multi-monitor aware** — use one unified grid or a separate HUD per display
- **Space names** — label spaces like _Code_, _Web_, or _Music_ instead of memorising numbers
- **Five cell styles** — Rectangles, Hybrid, Icons, Thumbnails, or Simple

### Navigate without guessing

- Click a cell to focus its space
- Use arrow keys or Vim keys (`hjkl`) with grid-aware wrapping
- Press Return to focus the selected space; Escape closes the HUD
- Optional number-key jumps support multi-digit space numbers
- Pin a HUD so it stays open while you work

### Move windows visually

Drag a real window over any HUD cell and drop it there. Spacemap highlights the target, moves the window through yabai, and can focus the destination space when you choose.

### Make it yours

- Built-in and file-based themes
- HUD transparency, size, position, shadow, app-icon size, and labels
- Custom normal and pinned hotkeys, including media keys and F13–F20
- Optional menu-bar workspace dots or miniature window-layout previews
- ScreenCaptureKit thumbnails on macOS 14+
- Sparkle updates: automatic, notify-only, or off

---

## Download

<div align="center">

<a href="https://github.com/wiggly-sheets/Spacemap/releases/latest"><img src="https://img.shields.io/badge/download-Spacemap-2EA043?style=flat&logo=apple&logoColor=white" alt="Download Spacemap" /></a>

</div>

---

## Installation

Install with Homebrew, or download a signed and notarized DMG from the [latest release](https://github.com/wiggly-sheets/Spacemap/releases/latest).

### Install with Homebrew

```bash
brew install wiggly-sheets/spacemap/spacemap
```

Update later with:

```bash
brew update && brew upgrade wiggly-sheets/spacemap/spacemap
```

### Install manually

1. Download the `.dmg` from the [latest release](https://github.com/wiggly-sheets/Spacemap/releases/latest).
2. Open it and drag **Spacemap** into **Applications**.
3. Open Spacemap once.
4. In **System Settings → Privacy & Security → Accessibility**, enable Spacemap.
5. Start yabai, then press <kbd>Ctrl</kbd> + <kbd>Space</kbd>.

> [!TIP]
> Every release includes `checksums.txt`. To verify a downloaded DMG:
>
> ```bash
> cd ~/Downloads
> shasum -a 256 Spacemap*.dmg
> ```
>
> Compare its hash with the matching line in `checksums.txt` on the release page.

> [!WARNING]
> If macOS quarantines a manually downloaded build, first prefer downloading the signed release again. As a last resort:
>
> ```bash
> xattr -d com.apple.quarantine /Applications/Spacemap.app
> ```

---

## Requirements

- macOS 13 or later; macOS 14+ for thumbnail cells
- [yabai](https://github.com/koekeishiya/yabai) running
- Accessibility permission for Spacemap
- Screen Recording permission only when using thumbnail cells
- **Automatically rearrange Spaces based on most recent use** disabled in **System Settings → Desktop & Dock → Mission Control**
- **Displays have separate Spaces** enabled for independent multi-monitor HUDs

Install yabai with Homebrew if needed:

```bash
brew install asmvik/formulae/yabai
```

You can use [skhd](https://github.com/koekeishiya/skhd) or [skhd.zig](https://github.com/jackielii/skhd.zig) for additional grid-navigation bindings. Spacemap works independently of either.

---

## Using Spacemap

### Everyday controls

| Action | Result |
|---|---|
| <kbd>Ctrl</kbd> + <kbd>Space</kbd> | Toggle HUD |
| Arrow keys / <kbd>h</kbd><kbd>j</kbd><kbd>k</kbd><kbd>l</kbd> | Navigate selected cells when enabled |
| <kbd>Return</kbd> | Focus selected space |
| <kbd>Escape</kbd> | Close HUD |
| Click a cell | Focus that space |
| Drag window onto a cell | Move it to that space |
| <kbd>⌘</kbd> + <kbd>,</kbd> | Open Settings while HUD or menu is open |
| <kbd>⌘</kbd> + <kbd>R</kbd> | Restart from menu bar |

### Settings

Open Settings from the menu bar or the HUD shortcut. Changes save immediately.

| Section | What it controls |
|---|---|
| **Grid** | Space limit/layout, display behavior, cell style, labels, icon strip |
| **Space Names** | Name visibility and per-space names |
| **Appearance** | Theme, background, opacity, scale, icon size, HUD shadow |
| **Behavior** | Hotkeys, HUD position, auto-hide, key navigation, drag-drop focus, menu bar, updates |
| **Debug/Advanced** | Signal socket health, diagnostics, extra window records |

### Deep links

Use these from shortcuts, scripts, Raycast, or other automation:

| URL | Result |
|---|---|
| `spacemap://toggle-hud` | Toggle HUD |
| `spacemap://pin-hud` | Show and pin HUD |
| `spacemap://settings` | Open Settings |
| `spacemap://menu` | Open menu-bar menu |
| `spacemap://config` | Open config file |
| `spacemap://themes` | Open themes folder |

### Command line

Launching the app from Applications installs `spacemap` and its manual page when permission allows. You can also run `make install-cli` from a checkout.

```bash
spacemap --version       # print version
spacemap --trigger       # toggle HUD
spacemap --space next    # focus next space, then show HUD
spacemap --space 4       # focus space 4, then show HUD
spacemap --space web     # focus yabai space label "web"
spacemap --settings      # open Settings
spacemap --config        # open config file
```

`--space` accepts `1`–`16`, `prev`, `next`, `first`, `last`, `recent`, `mouse`, or a yabai space label.

```bash
# Example skhd bindings
ctrl - right : spacemap --space next
ctrl - left  : spacemap --space prev
```

Read the installed manual with `man spacemap`.

---

## Configuration

Spacemap stores configuration in:

```text
~/.config/spacemap/config.toml
```

Settings is best for day-to-day changes. The TOML file is useful for dotfiles and automation. Missing or invalid fields repair individually; the prior file is saved as `config.toml.bak`.

```toml
[grid]
cols = 8
rows = 2
maxSpaces = 16
cellStyle = "rects"              # rects, hybrid, icons, thumbnails, simple
multiMonitorHUDMode = "unified"  # unified or separate
showSpaceNumbers = true
showIconStrip = true

[appearance]
theme = "default"
uiScale = 0.5
backgroundAlpha = 0.3
hudShadow = true

[behavior]
autoHideTimeout = 5
useArrowKeys = false
useVimKeys = false
jumpToSpaceEnabled = false

[behavior.hotkey]
keyKind = "keyCode"
keyCode = 49
modifiers = ["ctrl"]
```

<details>
<summary><b>Configuration reference</b></summary>

<br/>

| Table | Useful keys |
|---|---|
| `[grid]` | `cols`, `rows`, `maxSpaces`, `cellStyle`, `showMode`, `multiMonitorHUDMode`, `unifiedHUDVisibility`, `separateHUDVisibility`, `displayNavigationWrap` |
| `[spaceNames]` | `showSpaceNames`; names live in `[spaceNames.names]` as quoted space-number keys |
| `[appearance]` | `theme`, `mode`, `backgroundAlpha`, `hudShadow`, `uiScale`, `iconScale`, `showSpaceNumbers`, `showIconStrip`, `showMultiAppIcons`, `hideMenuBarIcon` |
| `[behavior]` | `autoHideTimeout`, `useArrowKeys`, `useVimKeys`, `jumpToSpaceEnabled`, `hudPosition`, `focusSpaceOnWindowDrop`, `focusSpaceOnWindowDropModifier`, `showHUDOnSpaceChange`, `updateMode` |
| `[advanced]` | `socketHealthInterval`, `showExtraWindows` |

Space names example:

```toml
[spaceNames.names]
"1" = "Desktop"
"2" = "Code"
"3" = "Web"
"4" = "Music"
```

</details>

---

## Updating

Spacemap uses Sparkle for in-app update checks. Choose **Auto**, **Notify**, or **Off** under **Settings → Behavior → Automatic Updates**.

Homebrew users can update with:

```bash
brew update && brew upgrade wiggly-sheets/spacemap/spacemap
```

Manual installs can download the newest DMG from [Releases](https://github.com/wiggly-sheets/Spacemap/releases/latest), drag it over the old copy in Applications, and choose **Replace**. Your configuration stays in `~/.config/spacemap/`.

---

## Build from source

### Prerequisites

- macOS 13+
- Xcode 15+ or Command Line Tools
- yabai and Accessibility permission for live testing

### Build, run, test

```bash
git clone https://github.com/wiggly-sheets/Spacemap.git
cd Spacemap

make run       # build, install, launch
make test      # unit tests
make app       # assemble Spacemap.app
make dmg       # universal DMG
```

For an Xcode project:

```bash
python3 scripts/generate-xcodeproj.py
open spacemap.xcodeproj
```

Architecture-specific bundles:

```bash
make app-arm64
make app-x86_64
make app-universal
```

> [!TIP]
> Accessibility permission belongs to the `.app` bundle, not a raw executable. Reinstalling changes the app hash. For a clean local permission cycle, use `make dev1`, remove Spacemap from Accessibility settings, then run `make dev2` and grant access again.

---

## Troubleshooting

| Problem | Try this |
|---|---|
| HUD does not appear | Confirm Spacemap has Accessibility permission, then reopen it |
| No spaces or windows | Confirm `yabai` is running and executable at `/opt/homebrew/bin/yabai` or `/usr/local/bin/yabai` |
| Thumbnails are blank | Grant Screen Recording permission, then reopen the HUD |
| Layout moves unexpectedly | Disable macOS **Automatically rearrange Spaces based on most recent use**, then log out and back in |
| Multi-monitor HUD is wrong | Enable **Displays have separate Spaces**, then log out and back in |
| Config change seems ignored | Close/reopen HUD; hotkey changes apply immediately from Settings |
| App will not launch | Check Console.app for “spacemap”; reinstall with `make dev1` then `make dev2` in a checkout |

---

## Documentation and contributing

| Document | Purpose |
|---|---|
| [Support](SUPPORT.md) | Get help or report a problem |
| [Security policy](SECURITY.md) | Report a vulnerability responsibly |
| [Contributing](CONTRIBUTING.md) | Contribute code or documentation |
| [Developer guide](DEVELOPER.md) | Technical implementation notes |
| [Reference](REFERENCE.md) | Detailed config and command reference |
| [Roadmap](DesignDocs/TASKS.md) | Planned work and known issues |
| [Changelog](CHANGELOG.md) | Release history |

---

## Inspired by

- [yabai](https://github.com/koekeishiya/yabai)
- [WindowMaker](https://www.windowmaker.org/)
- [YabaiGridSpaces](https://codeberg.org/mikkelricky/hammerspoon/src/branch/main/Spoons/YabaiGridSpaces.spoon)
- [skhd](https://github.com/koekeishiya/skhd) and [skhd.zig](https://github.com/jackielii/skhd.zig)

---

## License

Spacemap is released under the [MIT License](LICENSE). You are free to use, read, modify, and distribute it.
