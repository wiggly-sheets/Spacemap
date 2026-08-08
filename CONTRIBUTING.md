# Contributing to Spacemap

## Welcome!

We're excited to have you contribute to Spacemap. This is a native macOS utility that visualizes yabai workspaces in a floating 2D grid overlay.

## Development Workflow

### Prerequisites
- macOS 13+ (Ventura or later)
- Xcode Command Line Tools: `xcode-select --install`
- yabai installed: `brew install asmvik/formulae/yabai`
- skhd installed: `brew install koekeishiya/formulae/skhd` (or `brew install jackielii/formulae/skhd-zig`)

### Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/wiggly-sheets/spacemap.git
   cd spacemap
   ```

2. **Build the app:**
   ```bash
   make app
   ```

3. **Install and launch:**
   ```bash
   make dev1  # Uninstall if already installed
   # Remove spacemap from System Settings → Privacy & Security → Accessibility
   make dev2  # Rebuild, reinstall, and launch
   ```

4. **Grant Accessibility permission** when prompted.

### Building & Running

| Command | Description |
|---------|-------------|
| `make build` | Build release binary |
| `make app` | Build and assemble `.app` bundle |
| `make run` | Build, install to `/Applications`, and launch |
| `make test` | Run unit tests via swift test |
| `make dev1` | Uninstall from `/Applications` |
| `make dev2` | Rebuild, reinstall, and launch |
| `make clean` | Remove build artifacts |
| `make config` | Create default config file |
| `make dmg` | Build universal DMG |
| `make dmg-arm64` | Build ARM64 DMG |
| `make dmg-x86_64` | Build Intel DMG |
| `make release RELEASE=x.y.z` | Bump version, commit, tag, push (triggers release) |

## Code Style

- **Swift 5.9+** with Swift Package Manager
- **No external dependencies** - pure AppKit + SwiftUI
- **Follow existing code style** - consistency is key
- **No forced unwraps** - use `guard`/`if let` safely
- **Minimal comments** - write self-documenting code

## Contribution Guidelines

### Bug Fixes
1. **Reproduce the issue** - document steps to trigger it
2. **Fix the root cause** - don't bandage symptoms
3. **Test thoroughly** - verify fix works in all scenarios
4. **Update docs** - add notes to `DesignDocs/TASKS.md` if needed

### New Features
1. **Check DesignDocs/TASKS.md** - see if it's already planned
2. **Open an issue first** - describe the feature and get feedback
3. **Start small** - minimal viable implementation
4. **Test with yabai** - verify actual workspace interactions

### Code Changes
- **Edit existing files only** - no new files unless absolutely necessary
- **Small diffs** - 1-2 file edits preferred
- **No refactors** - don't rewrite entire modules
- **No comments** - keep it lean, add only if absolutely required

### Pull Requests
- **Title format:** `verb: what changed` (e.g., `Fix: handle yabai not running`)
- **Description:** brief explanation of changes and testing steps
- **Screenshots:** if UI changes, include before/after images

## Important Constraints

1. **yabai path:** Auto-detected at `/opt/homebrew/bin/yabai` (ARM) or `/usr/local/bin/yabai` (Intel)
2. **Accessibility:** Required for hotkeys, handled on launch
3. **Permissions:** Rebuilds revoke permissions - use `make dev1`/`dev2` workflow
4. **Config:** Reloaded on every HUD open (except `HOTKEY` which needs restart)

## Testing

### Unit Tests
```bash
make test             # Run all tests
swift test            # Direct SPM test runner
swift test --filter ConfigTests   # Run a specific test class
```

193 tests across 9 files, including config migration/healing, hotkey/media-key recovery, models, grid rendering, navigation, themes, deep links, thumbnail capture, and CLI installation.

### Manual Testing Checklist
- [ ] Launch app with yabai running → HUD opens on hotkey
- [ ] Switch spaces while HUD visible → active cell updates
- [ ] Click cell → switch space and close HUD
- [ ] Drag window over cell → window moves to target space
- [ ] Config change → HUD reflects new settings on next open
- [ ] Settings sidebar remains visible, highlights the selected category, and swaps to a separate detail form
- [ ] Every Settings category auto-saves its controls
- [ ] Kill yabai → app shows error dialog and exits
- [ ] Deny Accessibility → app prompts for permission
- [ ] Auto-hide → HUD closes after timeout

### Common Test Scenarios
1. **Config parsing:** Add inline comments (`# comment`) and verify parsing
2. **Scale testing:** Set `UI_SCALE=0.5` → verify 5× size
3. **Theme testing:** Set `THEME=tokyonight` → verify colors
4. **Signal testing:** `yabai --signal --emit spacemap_show` → HUD shows

## Known Limitations

- **Homebrew only:** No other package managers supported
- **Icon flicker:** Re-fetching icons causes visual artifacts (IconCache mitigates)
- **Drag ambiguity:** Multi-window app drags may fall back to click proximity

## Getting Help

- Check `DEVELOPER.md` for technical deep-dive
- Check `DesignDocs/TASKS.md` for roadmap and known issues
- Check `SUPPORT.md` for where to get help and what to include in a report
- Check `README.md` for user-facing documentation

## Code of Conduct

- Be respectful and patient
- Focus on the code, not the person
- Accept constructive criticism gracefully
- Help others learn and grow

Thank you for contributing to Spacemap!
