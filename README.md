# Spacemap

A native macOS utility that shows your yabai workspace grid on demand. Press `Ctrl+PgDn` to toggle a floating overlay showing all your desktops as a 2D grid with window positions highlighted inside each cell.

> Inspired by [WindowMaker](https://www.windowmaker.org/) 

**Quick Demo of Spacemap**
[![Quick Demo](https://img.youtube.com/vi/oYN-4LCuQnE/0.jpg)](https://www.youtube.com/watch?v=oYN-4LCuQnE)

With [yabai](https://github.com/koekeishiya/yabai) and [skhd](https://github.com/asmvik/skhd) you can set up your desktop switching behavior to be on a grid in macOS. 
You just don't have any visual reference that your workspaces are laid out that way. It takes a lot of mental gymnastics to keep everything straight in your head.
Spacemap can help you find where you left your things.

Before you run off because I said yabai:
> You do not have to disable SIP System Integrity Protection to get this setup.

## Visualization of Spacemap on a workspace
Here I have 4 windows open and `Spacemap` is opened via: `Ctrl+PgDn` key sequence.
It is in the middle of the screen. You can see that we are on desktop 6 and there are 4 apps open.
<details><summary>Desktop Screenshot</summary>

<img width="1793" height="943" alt="Screenshot 2026-05-11 at 1 50 18 PM" src="https://github.com/user-attachments/assets/b9f2dafc-d309-4c80-98be-8d0e1f19cc17" />

</details>

## Configuration Examples
| spacemap screenshot | Spacemap config | skhd config |
|---------------------|-----------------|-------------|
| <img width="711" height="136" alt="Screenshot 2026-05-11 at 1 20 00 PM" src="https://github.com/user-attachments/assets/bd9958db-07ee-466b-934c-e12d28ebd0a3" /> | <img width="195" height="75" alt="Screenshot 2026-05-11 at 1 42 02 PM" src="https://github.com/user-attachments/assets/4d493154-e1b2-4772-a408-639da7e3abe1" /> | [skhdrc](docs/skhd-configurations/skhdrc-8-by-2) |
| <img width="713" height="137" alt="Screenshot 2026-05-11 at 1 19 31 PM" src="https://github.com/user-attachments/assets/d298e386-6bc2-4ac3-8ba0-7184e2f072a5" /> | <img width="204" height="76" alt="Screenshot 2026-05-11 at 1 41 03 PM" src="https://github.com/user-attachments/assets/1a911ef2-5cb7-4746-87d1-92dddb9ec8b4" /> | [skhdrc](docs/skhd-configurations/skhdrc-8-by-2) |
| <img width="714" height="139" alt="Screenshot 2026-05-11 at 1 40 41 PM" src="https://github.com/user-attachments/assets/a4595e8b-2494-4d3b-b8cc-fcc41a4daf61" /> | <img width="199" height="76" alt="Screenshot 2026-05-11 at 1 42 45 PM" src="https://github.com/user-attachments/assets/522bc241-8d8a-4221-aad1-cc6e2e20a500" /> | [skhdrc](docs/skhd-configurations/skhdrc-8-by-2) |
| <img width="364" height="247" alt="Screenshot 2026-05-11 at 1 18 47 PM" src="https://github.com/user-attachments/assets/2eddfbc2-74a9-41dd-9d9a-cdba4f537232" /> | <img width="204" height="77" alt="Screenshot 2026-05-11 at 1 44 32 PM" src="https://github.com/user-attachments/assets/883414bb-b983-47e4-99bf-f46dd5484005" /> | [skhdrc](docs/skhd-configurations/skhdrc-4-by-4) |


Window positions are drawn as colored rectangles inside each cell (one color per app, derived from app name). The active cell updates instantly as you switch desktops, driven by yabai's `space_changed` signal.

## Usage

| Action | Result |
|--------|--------|
| `Ctrl+PgDn` | Toggle HUD open/closed |
| Arrow keys (←↑↓→) | Navigate spaces in grid (when enabled) |
| Vim keys (hjkl) | Navigate spaces in grid (when enabled) |
| `Escape` | Close HUD |
| `Return` | Jump to selected space |
| Switch desktops while HUD is open | Active cell updates live |
| Click on a workspace | Switches to workspace and closes spacemap |
| Drag a window onto a cell | Moves the window to that space |
| Menubar icon → Settings (⌘+,) | Open settings window |
| Menubar icon → Launch at Login | Toggle auto-start on login |
| Menubar icon → Show/Hide Map | Toggle HUD |
| Menubar icon → Restart Spacemap (⌘+R) | Restart the app |

## Run Requirements

- macOS 13+ (macOS 14+ for thumbnail cell style)
- [yabai](https://github.com/koekeishiya/yabai) installed and running
- [skhd](https://github.com/koekeishiya/skhd) (or [skhd.zig](https://github.com/jackielii/skhd.zig)) installed and running (for grid navigation)
- Accessibility permission (prompted on first launch). This is not the same as disabling SIP protection, which is not required.
- Screen Recording permission (only needed for thumbnail cell style)



On first launch of Spacemap macOS will prompt for Accessibility permission. Grant it — Spacemap needs it to monitor the global Ctrl+PgDn hotkey.

If you plan to use the **Thumbnails** cell style, you will also need to grant **Screen Recording** permission. You can do this from the menubar menu → "Open Screen Recording Permissions".
<details><summary>Accessibility Permissions Screenshot</summary>
<img width="722" height="844" alt="Screenshot 2026-05-10 at 10 58 32 AM" src="https://github.com/user-attachments/assets/b6d90393-2100-44bc-ac6f-00fe1de66a98" />
</details>


## Configuration Details

Config is read from `~/.config/spacemap/config` on every HUD open (no restart needed after editing, except `HOTKEY` which requires a restart):

```bash
GRID_COLS=8
GRID_ROWS=2
CELL_STYLE=rects
```

### Display options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `CELL_STYLE` | `rects`, `icons`, `thumbnails` | `rects` | How windows are drawn in each cell. `thumbnails` requires Screen Recording permission |
| `THEME` | theme name | `default` | Color theme. Edit `.smthemes` files in `~/.config/spacemap/themes/` to customize or add new themes |
| `VIM_KEYS` | `true`, `false` | `false` | Navigate spaces with hjkl when HUD is visible |
| `ARROW_KEYS` | `true`, `false` | `false` | Navigate spaces with arrow keys when HUD is visible |
| `UI_SCALE` | `0.0`–`1.0` | `0.5` | Scale multiplier for HUD size (effective: 0.5×–4.0×) |
| `BACKGROUND_ALPHA` | `0.0`–`1.0` | `0.3` | HUD background transparency (0=transparent, 1=opaque) |
| `MODE` | `dark`, `light`, `auto` | `auto` | HUD background appearance. `auto` follows system setting |
| `ICON_SCALE` | `0.0`–`1.0` | `0.5` | App icon size (effective: 0.2×–1.0×) |
| `SHOW_ICON_STRIP` | `true`, `false` | `true` | Show app icon strip at bottom of each cell |
| `SHOW_MULTI_APP_ICONS` | `true`, `false` | `false` | Show one icon per window (true) or one per unique app (false) in icon strip |
| `SHOW_SPACE_NUMBERS` | `true`, `false` | `true` | Show space number in top-left of each cell |
| `SHOW_SPACE_NAMES` | `true`, `false` | `true` | Show custom space names in center of each cell |
| `HIDE_MENUBAR_ICON` | `true`, `false` | `false` | Hide the menubar icon (app runs headless; use hotkey or CLI to toggle) |

```bash
UI_SCALE=0.5
THEME=catppuccin
BACKGROUND_ALPHA=0.3
MODE=auto
ICON_SCALE=0.5
SHOW_ICON_STRIP=true
SHOW_MULTI_APP_ICONS=false
SHOW_SPACE_NUMBERS=true
SHOW_SPACE_NAMES=true
HIDE_MENUBAR_ICON=false
```

### Grid options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `SHOW_MODE` | `all`, `active` | `all` | Show all spaces or only active displays |
| `MAX_SPACES` | `1`–`16` | `16` | Limit grid to N spaces |

```bash
SHOW_MODE=active
MAX_SPACES=8
```

### Auto-hide

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `AUTO_HIDE_TIMEOUT` | `0`–any | `5` | Seconds after last space change before HUD hides. `0` = never auto-hide |

```bash
# Hides 5 seconds after you stop switching spaces
AUTO_HIDE_TIMEOUT=5
```

### Hotkey

`HOTKEY` sets the keystroke that shows/hides Spacemap. Format: `modifier+modifier+key`. Requires a restart to take effect.

| Modifier tokens | Key tokens |
|-----------------|-----------|
| `ctrl`, `cmd`, `alt`, `shift` | `pgdn`, `pgup`, `space`, `tab`, `return`, `escape`, `home`, `end`, `left`, `right`, `up`, `down`, `f1`–`f12`, or any single letter/digit |

```bash
#HOTKEY=ctrl+pgdn     # default (Page Down)
#HOTKEY=ctrl+space    # alternative (conflicts with Cursor)
#HOTKEY=ctrl+shift+s  # example with multiple modifiers
```

### Space Names

`SPACE_NAMES` assigns custom names to spaces. Names appear in cell centers when `SHOW_SPACE_NAMES=true`.

```bash
SPACE_NAMES=1:Desktop,2:Dev,3:Media,4:Music
```
 
## Example configs

Get a copy of the example configs and place them in `~/.config/spacemap/config`:

```bash
# 4x4 icons grid (compact)
cp docs/config-examples/spacemap-config-4x4-hybrid ~/.config/spacemap/config

# 8x2 rects grid (classic)
cp docs/config-examples/spacemap-config-8x2-rects ~/.config/spacemap/config
```

## Install (in 5 steps)
1. Install prerequisites
2. Install spacemap
3. Grant Accessibility permission
4. Configure skhd (or skhd.zig)
5. Configure Spacemap

**Step 1: Install prerequisites**
```
brew install asmvik/formulae/yabai
brew install koekeishiya/formulae/skhd
# or: brew install jackielii/formulae/skhd.zig
```

**Step 2: Install spacemap**
```
brew tap jsheffie/tap
brew install --cask jsheffie/tap/spacemap
```

Or download the DMG from [releases](https://github.com/jsheffie/spacemap/releases), open it, and drag `Spacemap.app` to the Applications symlink. On first launch, Spacemap will ask if you want to move itself to /Applications.

**Step 3: Grant Accessibility Permission**

Launch Spacemap once to trigger the permission prompt:
```bash
open /Applications/spacemap.app
```

Then go to **System Settings → Privacy & Security → Accessibility** and enable Spacemap. The Ctrl+PgDn hotkey activates automatically — no restart needed.

**Step 4: Configure skhd (or skhd.zig)**

Copy the 8×2 grid keymap into your skhd config:
```bash
curl -fsSL https://raw.githubusercontent.com/jsheffie/spacemap/main/docs/skhd-configurations/skhdrc-8-by-2 \
  > ~/.config/skhd/skhdrc
```

Then restart skhd (or skhd.zig):
```bash
skhd --restart-service
```

**Step 5: Configure Spacemap**

```bash
mkdir -p ~/.config/spacemap
cat > ~/.config/spacemap/config << 'EOF'
GRID_COLS=8
GRID_ROWS=2
CELL_STYLE=icons
EOF
```

Press `Ctrl+PgDn` to open Spacemap.


## Build Requirements
- Xcode Command Line Tools (`xcode-select --install`)

## Building

**Quick build and run:**
```bash
make run
```

**Xcode project** (for IDE workflow):
```bash
python3 scripts/generate-xcodeproj.py
open spacemap.xcodeproj
```
The Xcode project is generated from SPM — 4 targets: default, arm64, x86_64, universal.

**Architecture-specific builds:**
```bash
make build-arm64      # Apple Silicon only
make build-x86_64     # Intel only
make build-universal  # Both architectures
make app-arm64        # .app bundle (ARM)
make app-x86_64       # .app bundle (Intel)
make app-universal    # .app bundle (universal)
```

## Testing

```bash
make test             # Run all unit tests via swift test
swift test            # Direct SPM test runner
swift test --filter ConfigTests   # Run a specific test class
```

112 tests across 5 files covering hotkey parsing, config parsing, theme loading, model encoding, grid computation, and cell view logic.

## CI/CD

**On push/PR:** `ci.yml` runs `swift test` + `swift build` on macOS-14.

**On tag push:** `release.yml` builds 3 DMG variants (ARM64, x86_64, universal) + `checksums.txt`, uploaded as GitHub release assets.

Dependabot watches `.github/workflows/` weekly for action updates.

## Makefile targets

| Target | Description |
|--------|-------------|
| `make dmg` | Build and package app into `spacemap-<version>.dmg` with /Applications symlink |
| `make dmg-arm64` | Build ARM64 DMG |
| `make dmg-x86_64` | Build Intel DMG |
| `make dmg-universal` | Build universal DMG |
| `make run` | Build, install, and launch |
| `make dev1` | Uninstall; pause to remove Accessibility permission in System Settings |
| `make dev2` | Reinstall and relaunch; grant Accessibility permission when prompted |
| `make test` | Run unit tests via swift test |
| `make build-arm64` | Build for Apple Silicon only |
| `make build-x86_64` | Build for Intel only |
| `make build-universal` | Build universal binary |
| `make config` | Create default config file if missing |
| `make distconfig` | Overwrite config with defaults (`CELL_STYLE=icons`) |
| `make permissions` | Print instructions for fixing a broken hotkey |
| `make uninstall` | Kill app and remove from /Applications |
| `make clean` | Remove build artifacts |
| `make install-cli` | Install CLI symlink to `/usr/local/bin/spacemap` |
| `make uninstall-cli` | Remove CLI symlink from `/usr/local/bin/spacemap` |

## CLI Usage

Once installed via `make install-cli`, you can use Spacemap as a command-line tool:

```bash
spacemap --version    # Print version and exit
spacemap --trigger    # Toggle HUD visibility and exit
spacemap --show-menu  # Show menu bar dropdown (app continues running)
spacemap --settings   # Open settings window directly (app continues running)
spacemap --config     # Open config file in default editor and exit
spacemap --help       # Print help and exit
```

Without any options, Spacemap launches and waits for the hotkey (Ctrl+PgDn) to toggle the HUD.

Without installing the CLI, you can still run the commands directly:
```bash
/Applications/spacemap.app/Contents/MacOS/spacemap --version
```

## Documentation

| File | Purpose |
|------|---------|
| [AGENTS.md](./AGENTS.md) | Project overview, architecture, development workflow |
| [DEVELOPER.md](./DEVELOPER.md) | Technical deep-dive, debugging, configuration details |
| [REFERENCE.md](./REFERENCE.md) | Quick commands, config keys, API docs, class reference |
| [TASKS.md](./TASKS.md) | Roadmap, planned features, bug fixes, known issues |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Guidelines for external contributors |

## Developer notes

macOS grants Accessibility permission to the `.app` bundle as a whole, not the raw binary. Running the binary directly bypasses the bundle context and the permission check fails silently.

### Accessibility permission is revoked on every reinstall

Every time you rebuild and reinstall, macOS revokes the Accessibility permission because the binary hash changes. The two-step dev workflow handles this:

1. `make dev1` — uninstalls the app; go to **System Settings → Privacy & Security → Accessibility** and click **−** to remove `Spacemap`
2. `make dev2` — reinstalls and relaunches; grant the permission prompt that appears

`make permissions` prints this reminder.

### The permission flow

On launch, spacemap calls `AXIsProcessTrustedWithOptions(prompt: true)` if not trusted, which opens System Settings to the Accessibility page. After you toggle it on, the app polls every second and registers the hotkey automatically — no restart needed.

## Troubleshooting

### HUD doesn't appear on hotkey
1. Verify Accessibility permission is granted (System Settings → Privacy & Security → Accessibility)
2. Check Console.app for "permission not granted" logs
3. Restart the app

### yabai not found error
yabai is auto-detected at `/opt/homebrew/bin/yabai` (ARM) or `/usr/local/bin/yabai` (Intel). Ensure yabai is installed: `which yabai`.

### Config not taking effect
Most config keys reload on HUD open. Close and re-open the HUD (`Ctrl+PgDn` twice). If it's `HOTKEY`, restart the app.

### Space names not showing
Verify `SPACE_NAMES` format: `SPACE_NAMES=1:Desktop,2:Dev,3:Media` (comma-separated, no spaces around `:`).

### App won't launch
Check Console.app for crash logs. Ensure yabai is running (the app checks on launch and shows an alert if not). Reinstall with `make dev1` → `make dev2`.

### How do I view logs?
Open Console.app, filter by process "spacemap" or subsystem "spacemap".

### How do I send a test signal to the HUD?
```bash
yabai -m signal --add label=test event=space_changed action="echo 'test' | nc -U /tmp/spacemap_$(whoami).socket"
```
Or connect to the socket and send `0` (refresh), `1` (show), `2` (hide).

### Can I use inline comments in config?
Yes: `KEY=VALUE # comment` works. The parser strips everything after `#`.

## Known Limitations

- **Homebrew only:** No other package managers supported.
- **Icon flicker:** Icons re-fetched on every render; IconCache mitigates.
- **Drag ambiguity:** Multi-window app drags may fall back to click proximity.

