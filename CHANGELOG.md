# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `[glyphStrip] plainPosition` and `plainMargin` place the strip on a display without a notch, independently from the notch anchors. Notch presets on a plain display no longer jump to the screen edge; the default is centred. Settings > Glyph Strip shows one position picker per screen type.

### Changed
- Custom glyph strip position and display identity are now saved separately for notched and plain displays. `plainCustomX`, `plainCustomY`, and `plainCustomScreen` hold the plain point. Lock Position stays one global toggle for both screen types.

### Fixed
- A notch-anchored glyph strip no longer parks against the far left or right screen edge on a display without a notch. Plain displays default to centred until their own placement is set.
- A custom-position glyph strip can be dragged into the menu bar row. It now rises above the menu bar there, so it stays visible and clickable; below the row it keeps the floating level.

## [2.2.2] - 2026-11-21

### Fixed
- The glyph strip now hides while Mission Control or Exposé is on screen, so it is no longer copied into every space thumbnail. Detection uses the same window-server shield check as menu-titles, and needs no setting: the strip always hides there and returns when Mission Control closes.
- The HUD also hides while Mission Control or Exposé is on screen, and refuses to open until it closes, so it no longer appears in space thumbnails. It shares the glyph strip's detection and needs no setting.

## [2.2.1] - 2026-11-21

### Fixed
- The app no longer relaunches itself when macOS answers a permission probe with a transient AX error such as `kAXErrorCannotComplete`, or when a permission check stalls. Only a disabled Accessibility API or a revoked trust bit counts as a revocation. Real revocations still release the event taps and relaunch the app.

## [2.2.0] - 2026-11-20

### Added
- `[hudKeys]` gains the `previousSpace` and `nextSpace` commands, bound to `p` and `n` by default, stepping through existing spaces and wrapping at either end. Empty grid cells in an `.all` grid are skipped, and in separate mode the step stays on the focused display. Every existing HUD key keeps its default, and both commands can be rebound or unbound in Settings > Hotkeys.
- Typed letters for a space-name jump now show the prefix struck through in the drop-target colour while no existing space name matches it, the same miss style as a typed space number that does not exist. A prefix that matches clears the strike as soon as it resolves. Letters bound to an active `[hudKeys]` command still run that command instead of entering the prefix.
- `[behavior] fuzzySpaceJumpEnabled` (default `true`) and a Settings > Hotkeys > Hotkeys toggle, "Jump to Space by Name", turn space-name letter jumps off without disabling number jumps. The two jump toggles are independent. The toggle reads off and the jump is ignored while space names are hidden; the saved value returns when names are shown again.
- The menu-bar glyph strip now paints the background material from the same `[glyphStrip]` keys as the floating strip. Menu-bar mode offers solid or transparent only; selecting it while Liquid Glass is saved switches the material to solid, as does loading such a config, because a status item cannot host a backdrop blur without flashing black on space switches. Anything else paints the solid fill. Corner radius, border, and theme are shared. The floating strip keeps the real glass and its variant.

### Changed
- The glyph strip has one background shape instead of a shape picker: `cornerRadius` alone decides between square ends (0), a rounded rectangle, and a pill (half the strip height or more). `shape` is no longer written or read. A transparent background no longer offers a shape or radius to set.

### Fixed
- The menu-bar glyph strip's hover highlight now covers the whole segment, including the left edge of a space number.
- The floating strip's hover highlight uses the theme colour instead of the system selection colour.
- A transparent floating strip no longer gives every glyph a black outline: the panel only casts a window shadow when it paints a backdrop.
- Vertical padding now grows a free-placed horizontal strip, so Same Padding on All Sides changes the top and bottom gaps as well as the sides. An anchored strip stays the menu-bar row height.
- Settings > Glyph Strip hides Shape and Background Corner Radius while Background Material is Transparent, because no background is drawn to shape. Matching the HUD still shows the picker, since the HUD's material may draw one.

## [2.1.0] - 2026-11-20

### Added
- `[spaceNames] namingMode` (`custom`, `auto`) lets spaces name themselves. In `auto` mode each space takes up to `autoNameAppCount` (1-3, default 3) visible apps in reading order, joined by `·` with a trailing `…` when the space has more apps than shown; that name feeds the HUD cells, `names`/`both` strip labels, and fuzzy name jumps. Typed names and profiles stay saved and reappear when you switch back to `custom`; auto names are never written to the config. `custom` is the default and keeps today's behavior.
- Typing letters with the HUD visible fuzzy-matches space names and jumps: the typed prefix matches names by exact prefix first, then as an in-order subsequence, and jumps as soon as one named space matches. It collects for 0.3 s while several spaces still match, Backspace deletes a character, and Escape (when unbound) cancels the prefix. It shares the `jumpToSpaceEnabled` toggle and the digit readout with number entry; unnamed spaces are not candidates. Letters already bound in `[hudKeys]` or the legacy `[behavior]` keys still run their command.
- `[glyphStrip] spaceLabelStyle` (`numbers`, `names`, `both`) shows a space's name from the active space-name profile in the strip's label run, in place of or beside its number. A space with no name keeps its number; names longer than 12 characters are shortened with an ellipsis. The default `numbers` keeps today's strip unchanged.
- `[hudKeys]` gains the `moveSpaceBack`, `moveSpaceForward`, and `cycleLayout` commands, so the space-move keys and layout cycling are configurable in the same table as every other HUD key. They start unbound, like their old `[behavior]` keys.
- CLI commands for `--status`, `--print-config`, `--update`, and `--update-font`. Status reports the app path, config path, running state, and yabai availability; config printing emits the resolved TOML without launching the app; the update commands forward to the running app. `--version` also reads the app bundle through the CLI symlink instead of printing "Unknown".
- Every HUD action now has user-configurable shortcuts in Settings > Hotkeys and the `[hudKeys]` table. Defaults remain vim keys and arrow keys for movement, with the existing action keys for first/last/recent space, close, create, delete, and layouts.
- Config presets: a preset is one complete config.toml under `~/.config/spacemap/presets/`, applied from Settings > Advanced > Config Presets or with `spacemap --config-preset NAME`. Switching saves the current settings into the outgoing preset first, so edits made while a preset is active survive the next switch. Create a preset from the current config, from defaults, or from another preset.
- Import and export a full config file from Settings > Advanced. Exports leave out font install state, which is machine state rather than taste.

### Changed
- Every CLI flag now lives in one table that parse, the post-launch actions, single-instance forwarding, and the delivery check read, so flag recognition is table-driven across those four call sites. New parsing tests cover it. DEBUG builds now honour `--settings` and `--show-menu` at launch because that delivery check lost its `#if !DEBUG` gate; the App entry gate stays so an Xcode debug run still launches the HUD. Release behavior is unchanged: no flag, output, exit code, or socket command differs. Help text and the restart script still list their flags by hand.
- Settings now edits one `SettingsDraft` over the whole config instead of ninety separate seeded fields, and writes through a 0.5 s debounce: a burst of edits becomes one file write. The debounce is flushed on a pane switch, on window close, on quit, and before a preset apply or import, so an edit is never lost and never lands on a config that was just replaced.
- The Settings window draws its backdrop with `NSVisualEffectView` on every macOS version. `NSGlassEffectView` behind editable SwiftUI content flashed black while typing on Tahoe; behind-window blending still samples the desktop through the transparent window.
- HUD space names shrink to fit the cell width on one line, down to a third of the font size, instead of wrapping to two lines or overflowing long auto-generated names.
- Settings > Space Names shows the derived read-only names while auto naming is on, refreshed from the live spaces, instead of graying out the stored custom names. Switching back to custom still brings those names back.
- Launch now opens the relevant privacy pane when a permission is missing: Accessibility (titled Device Control and Data Access on macOS 27) before the drag helper, and Screen Recording when thumbnails are on.
- HUD window logic is split into two modules: showing, hiding, refresh staleness, and auto-hide live in `HUDPresenter`; space create/destroy/layout/move (with their yabai settle polling) live in `HUDSpaceCommands`. Internal only: fades, auto-hide timing, and refresh cadence are unchanged.
- Every HUD key now runs through one command map and one dispatch entry. The five `[behavior]` HUD hotkeys (`hudMoveSpaceBackHotkey`, `hudMoveSpaceForwardHotkey`, `hudNewSpaceHotkey`, `hudDeleteSpaceHotkey`, `hudCycleLayoutHotkey`) still decode from existing files and feed that map as bindings, and they are matched before `[hudKeys]` exactly as before, so a config with both keeps the scalar binding. Settings > Hotkeys > HUD Keys now lists one editor per command, including the space-move and cycle-layout keys; saving folds any legacy scalar binding into the map and writes those scalar keys unbound.
- Both panels now store their position one way in `config.toml`: a fraction of the screen plus the display's identity. The HUD's custom position rides in `[behavior.hudPosition]` (`x`/`y` plus an optional `screen`), and the free-placed glyph strip uses `[glyphStrip] customX`/`customY`/`customScreen`, so a position survives monitor changes and one placement fix covers both surfaces. Saved positions reset once on upgrade: re-drag the HUD or the strip to place it again.
- `config.toml` now reads and writes through one schema table (`ConfigSchema`) for every key: decode, defaults, repair, and encode walk the same declarations, and the partial-values holder (`ConfigValues`) plus the `AppConfig` facade are gone. A repaired value now reaches the file on the repair save itself, so an out-of-range entry such as `spacesCornerRadius = 999` becomes the clamped value as soon as the config is re-saved instead of surviving until a later load rewrites it. Applying a preset resolves its text against the defaults and repairs first, so an invalid preset value lands in `config.toml` already healed.
- A free-placed glyph strip now measures the full screen, not the safe/visible frame, when it saves and replays its position; the safe area only decides when a tall strip wraps into extra columns. A dragged strip can therefore sit behind the Dock or the menu bar and stay there.
- `SpacemapConfig` is the name of the whole-app config value; `GridConfig` is gone.
- All three event taps (global hotkeys, window drag, HUD keys) now share one host (`EventTapHost`) for install, teardown, health checks, and permission-revocation recovery, with each consumer declaring only its event mask, thread placement, and handler. The fn-modifier rule no longer differs between global and HUD matching: a HUD binding with extra non-relevant modifiers now matches, and function-key bindings match without holding fn, same as global hotkeys. Tests inject the tap factory and the relaunch hook, so no test can restart the test host.
- The `[grid]` section of `config.toml` now reads and writes through one schema table (`ConfigSchema.gridFields`): decode, defaults, range repair, and section flattening walk the same 16 keys; the emitted TOML walks the same 15 grid lines plus the existing `[behavior]` line for `showThumbnailWallpaper`. Written output is byte-identical to the previous writer.
- The `[appearance]` section of `config.toml` now reads and writes through `ConfigSchema.appearanceFields`: the same table drives decode, defaults, repair (out-of-range appearance values the decoder accepts are clamped in memory when the file is repaired; values the decoder rejects fall back to defaults), section flattening, and the 30 emitted lines. Written output is byte-identical to the previous writer.
- The `[behavior]` section of `config.toml` now reads and writes through `ConfigSchema.behaviorFields` and `ConfigSchema.tableFields`: one declaration per key drives decode, defaults, repair (frequent-repair keys flag a rewrite; animation, drag-focus, and drop-mode enums heal silently), section flattening, the 23 scalar lines, all eight hotkey tables, `[hudKeys]`, and `[behavior.hudPosition]`. Written output is byte-identical to the previous writer.
- The `[advanced]` section of `config.toml` now reads and writes through `ConfigSchema.advancedFields`: the same table drives decode, defaults, repair (the socket-health interval clamps to 1...3600, and a missing `refuseUntrustedYabai` heals without a rewrite), section flattening, and the three emitted lines. Written output is byte-identical to the previous writer.
- The HUD panel and the glyph strip now share one panel presentation module (`PanelPresenter`) and one screen module (`ScreenContext`): panel creation, alpha fades, drag mechanics, quartz-frame flips, screen lookup, safe-area/dock detection, and fullscreen detection live in one place instead of two hand-rolled copies. `HUDGeometry` folded into `ScreenContext`. Panel behavior, fade ordering, and config formats are unchanged.
- Glyph strip rendering is now one `SegmentLayout` value from the pure model: slot frames, run frames, and the drag window mapping come from one render pass, the floating panel caches that render per bounds, and the menu-bar item caches the same render per button bounds. Per-run paint colour is applied when each run's attributed string is built rather than stored in the layout. This replaces the duplicated hit tests and the second window mapping in the panel. Frames, hit areas, and drag payloads are unchanged.
- HUD navigation is now edited as individual action bindings instead of the arrow-key, vim-key, and extended-key toggles. Each action accepts several shortcuts, and an empty list leaves that action unbound.
- Local installs, the CLI symlink target, and the move-to-Applications prompt now use `/Applications` again. `make run` installs there, and a copy in `~/Applications` no longer counts as installed.
- Theme loading, saving, and the editor's TOML writer are split into a pure `ThemeCodec` (parse a theme, format a colour, render the saved file) and a `ThemeStore` that takes its themes directory by injection. Every surface — HUD, glyph strip, Settings, Theme Library, deep links — shares the one store `SpacemapServices` owns, replacing the `ThemeManager` singleton. Theme files, the saved TOML shape, and the 20 bundled themes are unchanged.
- The yabai queries, the Spotlight icon lookup, and the yabai codesign trust check now run through one `ProcessRunner`: child spawn, drained stdout/stderr, exit status, and the SIGTERM-then-SIGKILL timeout policy live in one place instead of three hand-rolled copies. Timeouts, arguments, and output handling for yabai queries are unchanged.

### Removed
- Config parsing no longer accepts pre-2.0 key names: `hideMenuBarIcon`, `useThemeTint`, `glassAmount`, bare boolean `glyphStrip`, `backgroundStyle = "transparent"`, direct numeric keys under `[spaceNames]`, and per-style opacities that inherited `backgroundAlpha`. Missing per-style opacity keys now fall back to that style's own default.
- `customHUDX`/`customHUDY`, the glyph strip's `xOffset`/`yOffset` keys, and the `spacemap.hudCustomScreenIdentifier` UserDefaults entry are gone: the fraction-plus-screen scheme above replaces them. That also drops the strip's `yOffset` menu-bar nudge; anchored placements centre in the menu bar row.

### Fixed
- Auto space names now use the same window rules as the HUD, so helper windows yabai lists on a space (for example Plexamp) no longer name it. Windows the HUD only draws with Extra Windows show up in names only when that setting is on.
- Thumbnail cells now render on the native spaces glass, with the corner radius following the spaces settings. The space capture draws above the glass background.
- Switching the cell style to thumbnails no longer prompts for Screen Recording, or opens its System Settings pane, when the permission is already granted. Users who have not granted it still get the request and the pane.
- Yabai signal registration now verifies that yabai's signal table holds the `spacemap_space_changed` signal after the adds, and retries the remove-then-add pass with a bounded backoff (6 attempts over about 30 s) when the daemon is not ready yet. A daemon that has just restarted accepts a signal add and silently keeps nothing; Spacemap used to give up on the first silent failure, which froze the strip until the next restart.
- The glyph strip no longer freezes after yabai restarts while Spacemap is open. Spacemap notices the new yabai daemon, registers its signals again, and repaints the strip, so space changes highlight again without restarting Spacemap. The strip also repaints when a space change opens the HUD, and it keeps its last good frame while yabai is down instead of showing a lone add button.
- A theme editor field that is not a six-digit hex value now turns red and blocks Save, instead of silently saving that colour as black while the other fields saved normally.
- Saving Settings no longer duplicates a HUD key binding when a legacy `[behavior]` scalar key is the same key as an existing `[hudKeys]` entry for that command. The folded map keeps one binding, so the HUD key editor no longer shows the same shortcut twice.
- Dragging the HUD past a screen edge no longer resets its position to Center on the next open: the saved fraction is clamped to 0...1 instead of storing an out-of-range value the config loader rejects.
- A glyph strip straddling two displays now saves the display it covers most, so releasing it after a cross-display drag no longer makes it jump back to the other display.
- A hand-edited `[appearance]` value below its allowed range now resolves to the lower bound instead of the default, so a negative `spacesCornerRadius` renders square corners instead of snapping back to 4.
- HUD key editors no longer repeat the first action's rows in Settings when several actions have bindings. Each editor keeps its rows in one container instead of sharing row identities with its siblings.
- The menu-bar glyph strip now resolves a click against the pointer position instead of the cached hover segment, so a refresh that reflows the strip no longer makes the first click focus the old segment. Clicks also keep the command captured at press time, and a rebuilt status item drops any in-flight press and its global mouse monitor. A press whose release never arrives finishes once the physical button is up, and a tiny pointer wobble that crosses the drag threshold without reaching another space still runs the click.
- Menu-bar strip clicks now hit-test the physical pointer, because status-item events can deliver the item's center as the click point and repeatedly focus the same space. The command is still captured at press, so a refresh cannot retarget it. Clicks without a draggable run finish on the local release; drag-capable runs finish on the real release through the global monitor. Drags still start only from a space number or app icon.
- The menu-bar glyph strip now clears a frozen press and hover highlight after sleep without rebuilding the status item, so the first click after wake lands normally. Hover is reconciled against the physical pointer while a highlight is visible, so a missed exit or menu-bar reflow cannot leave a space highlighted.
- The menu-bar glyph strip now disappears for the visibility hotkey, fullscreen hiding, and when the strip is disabled. Hover and drop hit tests require the pointer inside the item, the add button works in menu-bar mode, and a drop keeps the space it targeted if a refresh reorders segments mid-drag.
- Font updates that need a restart now use the same detached relaunch helper as the Restart menu item. A failed helper launch leaves the app running instead of quitting without a replacement.
- A theme name that has no matching theme file is no longer treated as a broken value. The HUD still falls back to the default look, but config.toml keeps the name, so a pending catalog download, a removed custom theme, or a build without bundled themes can no longer silently reset the theme.
- Settings > Appearance no longer drops a Glass Style change: the picker now saves on change like its siblings, instead of only when another control was touched.
- The yabai binary trust check no longer hangs when `codesign` wedges: it shares the 10 s command timeout and reports the binary as unverifiable instead of blocking the check forever.
- The Move to Applications signature check and the MRU prompts now run their child processes (`codesign --verify`, `defaults read`, `defaults write`, `killall Dock`) through the shared `ProcessRunner` with a 10 s timeout, so a wedged child no longer blocks the move or the MRU check. Commands, arguments, output handling, and failure behavior are unchanged.

## [2.0.0] - 2026-11-16

### Added
- Bundle 20 popular iTerm2 themes and add a floating Theme Library with color previews, search, one-click install/remove, and Apply. The remaining catalog is fetched from the `spacemap-themes` index, cached, and refreshed once a day; bundled themes stay read-only.
- A locked glyph strip can reorder spaces by dragging a space number onto another segment, or move an app by dragging its icon onto a segment or a visible HUD cell. Dedupe moves every window of the app; one-icon-per-window mode moves only the dragged window. Hovering a segment highlights it and eases its content up briefly. Drop destinations highlight only the segment or HUD cell directly under the pointer, so the highlight matches the cursor and gaps clear it. Display separators and the add button are never drop targets, a space deleted mid-drag cancels the swap, the dragged space is not offered as its own HUD target, and the HUD and strip repaint again as yabai applies the reorder. On macOS 27.2 upstream yabai cannot move spaces, so Spacemap swaps their window contents instead; empty spaces and Mission Control order stay unchanged until a patched yabai is installed.
- Glyph strip `[glyphStrip] autoResizeMaxLength` (default 0, off): target width or height. Icon, number, and spacing sizes grow when there is spare room and shrink when over the target, with an 8pt legibility floor.
- Glyph strip padding can be locked to one value for all sides (default) or split into horizontal and vertical values. `padding`/`lockPadding` and `horizontalPadding`/`verticalPadding` control it, and separate vertical padding now insets horizontal strips too.
- Glyph strip `[glyphStrip] displayMode` (`floating` default or `menuBarItem`) places the strip in the menu bar instead of a floating panel. Menu-bar mode keeps contents, clicks, hover and space/app drags, but drops shape, glass, free placement and vertical layouts. General > Menu Bar now holds both the Spacemap menu-bar controls and the glyph-strip menu-bar toggle, and both items can be visible at once.

- Custom glyph-strip placement now uses the usable screen area (menu bar and Dock excluded) and also gives way to edge-anchored accessory windows such as third-party docks. A vertical strip that runs out of height wraps space blocks into extra columns instead of drawing off screen.
- HUD entrance styles: `fade`, slide from each screen edge, or scale, chosen with `hudEntranceStyle` and timed by `hudAnimationStyle`. Space cells now animate on insert and animate a slight scale on the drop target; the glyph strip fades in and out with the same motion setting.
- Glyph strip layout letters now follow the HUD: `showBSPLayoutBadge`, `showStackLayoutBadge`, `showFloatLayoutBadge` (default true) and bsp shows `b`. Vertical strips gain `verticalPadding` (default 4).
- Permissions page offers a small drag helper: drag the Spacemap icon into the Accessibility or Screen Recording list. It opens with a permission request and closes after an accepted drop.
- Typing a space number now jumps as soon as the digits can only mean one space instead of always waiting for the 0.3s timeout. A valid jump shows its number briefly while the HUD moves; a number that does not exist shows in the drop-target colour with a strike for 0.6s. A repeated digit replaces the entry instead of appending, so mashing 4 never shows 44, and the readout no longer re-renders the grid.
- Settings sidebar groups now expand into subsections, like IINA. The open group follows the pane as it scrolls, and clicking a subsection jumps straight to it.
- About → Software Used now credits sketchybar-app-font and Julian Windeck's liquid-glass project, with links to each source and license.
- `[appearance] backgroundStyle` (`glass` default / `solid`) plus `[appearance] glassStyle` (`clear` / `regular` / `tinted`, default `regular`): configurable HUD background. Clear is the light native material, Regular the frosted one, and Tinted draws the theme accent over `glassTintedMaterial` (`clear` or `regular`). Solid fills with the theme background color; at zero it is fully transparent. The old `opaque` and `frosted` names are not aliased; an existing config must use `regular`.
- `[appearance] hudCornerRadius` (default `10`): rounds the outside edge of the whole HUD panel without changing the space cells.
- Per-style HUD opacities (`glassClearOpacity`, `glassRegularOpacity`, `glassTintedOpacity`, `solidOpacity`) with `matchBackgroundOpacity` to link all styles to `backgroundAlpha`. Each style otherwise keeps its own remembered value.
- The glyph strip can now either keep its own complete appearance or `matchHUDAppearance`, copying the HUD's material, glass style, finish, opacity, and theme. Its own per-style opacities (`glassClearOpacity`, `glassRegularOpacity`, `glassTintedOpacity`, `solidOpacity`) are separate by default, with an optional shared `backgroundOpacity`.
- Glyph strip `hideInFullscreen` (default `false`): hides the strip while the focused space has a native-fullscreen window and brings it back on exit. yabai reports the flag per space, so a fullscreen window on another space does not hide it. Accessibility and window-size checks cover the case where yabai cannot tell.
- `[grid] showSpaceLayout` (default `false`): layout letter next to the space index (`f` float / `s` stack / `b` bsp; bsp is bare in the glyph strip). Requires `showSpaceNumbers`.
- Glyph strip `[glyphStrip] position = "custom"` now places the strip anywhere on the screen, not just the menu bar row, and `orientation = "vertical"` stacks one space per row for a side-of-screen strip. `verticalLayout = "stacked"` stacks each space's icons underneath its number. `lockPosition = true` pins a custom strip against drags; it is off by default. Dragging the strip saves the new offsets; the offset steppers are gone from Settings.
- HUD layout letters can be hidden per layout type (`showBSPLayoutBadge`, `showStackLayoutBadge`, `showFloatLayoutBadge`, all on by default). Only shown when Space Layout is on; hiding a letter leaves the badge blank but the space keeps its layout.
- Deleting the focused space now returns to the space before it instead of yabai's fallback to the first space.
- The Settings sidebar splits Behavior into Hotkeys, HUD, Navigation, Window Drop, HUD Feedback, Menu Bar, and Updates, so each group is one click away.
- HUD text colour override in Appearance. Leave it empty to follow the theme, or set a hex colour when a dark theme makes space numbers and names hard to read.
- Missing-space cells now use a clearer dashed outline: thicker line, wider dashes and stronger colour.
- The glyph strip now repaints on the leading edge of a change instead of waiting out the full debounce, reuses the parsed app-font face across refreshes, and keeps burst coalescing so space or window changes stay responsive without extra yabai queries.
- Custom themes can live in `.toml` files in `~/.config/spacemap/themes` (quoted hex values and `[colors]` sections), and Appearance gained a Theme Editor that clones the selected theme, edits any colour by picker or typed hex, and saves a TOML file. Saving an existing theme writes a separate `(Edited)` copy, so the original stays untouched; saving that copy updates it. Saving selects the theme; external file edits reload with the theme list.
- HUD motion is configurable through `[behavior] hudAnimationsEnabled` (default `true`) and `hudAnimationStyle` (`natural`, `springy`, `fast`). It fades the panel and animates cell focus, add, and delete changes. Turning it off makes every change instant.
- Thumbnails now draw the desktop wallpaper beneath the window captures, and off-screen windows are queried so spaces that are not visible still show their windows.

### Changed
- Removed the old hardcoded theme set and its first-run `.smthemes` seeding. The theme list now comes only from the 20 bundled iTerm2 themes and themes installed from the Theme Library. An existing `theme` name that no longer exists falls back to the default until another theme is chosen.
- Settings now groups by workflow: **General**, **Spaces**, **HUD**, **Glyph Strip**, **Hotkeys**, and **Advanced**. Space names and profiles sit under Spaces, and hotkeys have their own sidebar section instead of living under Behavior.
- Hotkeys gained a **HUD** subsection with configurable **Move Space Left** and **Move Space Right**, **New Space**, **Delete Space**, and **Cycle Layout** actions. They follow the Space Drag Action mode while the HUD is open.
- Settings shortcut recorders use native-looking keycaps: each modifier and key draws as its own small key, the field shows a focus ring while recording, and an unset shortcut reads “Not Set”.
- The app no longer bundles sketchybar-app-font. It downloads the current release on first launch, then checks daily under the automatic update mode; manual checks remain available. Font updates default to automatic, and replacing an already-loaded face restarts Spacemap because CoreText caches it by PostScript name.
- Memory trim: the window-space poll runs every second instead of every half second, the icon cache keeps 64 icons instead of 200, and hidden HUD thumbnail frames are dropped after 30 seconds unless the HUD reopens.
- Background Opacity now applies to every HUD background: glass uses it as the effect's own opacity, the way macOS menu-bar overlays do, and solid uses it as a plain see-through fill with no blur. Opacity is remembered per style unless “Use Same Opacity for All Styles” is on. Glass styles clamp to a floor so the lowest setting still shows glass (clear 35%, regular 40%, tinted 45%); solid may fade to zero.
- The HUD and glyph strip no longer offer a separate transparent style. Solid at zero opacity is the same result, so `transparent` in an existing config loads as `solid` with its old opacity.
- The glyph strip gains the same glass sub-types (`clear` / `regular` / `tinted` via `[glyphStrip] glassStyle`) and applies opacity to both solid and liquid-glass backdrops. The continuous `glassAmount` slider and `useThemeTint` toggle are replaced by the sub-type picker; both old keys still decode onto the closest sub-type. Opacities are per style unless linked, and the strip can match the HUD appearance instead of using its own.
- The Makefile follows the shared build vocabulary now: `make` prints the list of targets, and the targets are `help`, `build`, `test`, `app`, `app-arm`, `app-intel`, `app-universal`, `dmg`, `dmg-arm`, `dmg-intel`, `dmg-universal`, `release-artifacts`, `release` and `clean`. The old names `app-arm64`, `app-x86_64`, `dmg-arm64` and `dmg-x86_64` still work.
- `make release VERSION=x.y.z` no longer pushes. It writes the VERSION file and the Info.plist, commits them, tags `v<x.y.z>` locally and prints the command that pushes the commit and the tag. The push is the release, and it belongs to the person who runs the target.
- The release workflow no longer signs with a Developer ID identity and no longer notarizes, so every published build is ad-hoc signed. The published builds were already ad-hoc, because the Developer ID and notarization secrets were never set.
- The release workflow no longer writes a cask into the Homebrew tap. The consolidated `wiggly-sheets/homebrew-tap` renders its own cask from a template and follows the latest stable release, so a release needs no manual copy.
- The release notes now come from the section of `CHANGELOG.md` for the released version. A version without a section fails the release.
- `[behavior] showHUDInteractionFeedback` (default `true`): hide the typed-number readout and action notices over the HUD. Every action still runs; only the overlays disappear.
- `[behavior] spaceDropMode` (default `content`): choose whether dragging a space swaps window contents or moves the spaces themselves. Swap Contents works with any yabai build; Move Spaces needs space-move support.
- `[behavior] spaceDragFocus` (default `stay`) and `windowDragFocus` (default `destination`): choose whether focus stays, follows the drop, or returns to the original space after rearranging spaces or moving an app icon.
- HUD text font and size can be chosen with the native macOS font panel; the space-number size scales names and badges. Reset returns to the system font.
- The HUD icon strip can use a different icon source from hybrid and icon cells, through `hudIconStripSeparate` and `hudIconStripSource`; both default to following `hudIconSource`.
- HUD app icons can use sketchybar-app-font glyphs instead of native macOS images. The setting applies to cell icon grids, hybrid cells and the icon strip.
- Drag app icons in the HUD itself, not only in the glyph strip. A deduped app icon moves every window of that app; one-icon-per-window mode moves only the dragged window.
- HUD and glyph strip animate content arriving and leaving after a drop or reorder: HUD icons scale and fade into their new cell, and only the strip segments whose content changed pop in with a short stagger.
- `[behavior] presence` (`dock`, `menuBar`, `both`, `none`; default `menuBar`) replaces `hideMenuBarIcon` and adds the Dock as a place to show Spacemap. The menu-bar display pickers appear whenever the menu bar is included. Legacy `hideMenuBarIcon` still loads.
- `[grid] showThumbnailWallpaper` (default `true`): draw the desktop wallpaper behind thumbnail cells, or leave it transparent.
- The Advanced pane now reports Accessibility and Screen Recording status with request buttons and deep links into the matching System Settings panes. Thumbnail cells request Screen Recording the first time they are selected, and the app asks on launch when thumbnails are already configured.

### Fixed
- Clicking the menu-bar glyph strip targets the visibly hovered segment, even if the status item reflows before release. A drag that moves past the threshold is no longer treated as a click, so it cannot focus the wrong space on mouse-up.
- Dragging from the menu-bar glyph strip now survives the status item's own early mouse-up. The gesture finishes on the real release, so space reorders and app moves reach their destination.
- After a sketchybar-app-font update, Spacemap restarts when the strip had already loaded a face. CoreText pins the old face by PostScript name, so an in-place swap drew the previous release's glyph shapes.
- The HUD and glyph strip now notice a window moving to another space. yabai emits no signal for `window --space`, so a lightweight window-to-space fingerprint is polled twice a second and triggers a refresh on change.
- Permission checks no longer run on the main thread. TCC can stall while Spacemap is removed from Device Control & Access; the probe times out and tears its event taps down instead of freezing every click and key. Event taps are disabled before their run-loop source is detached, and a revoked HUD tap relaunches Spacemap so the WindowServer always releases the old tap.
- The HUD no longer swallows every key while visible. It captures only key presses it acts on, so a stale or revoked Accessibility tap cannot lock out the keyboard.
- A glyph strip can be dragged to any screen edge again; the safe area now only decides when a tall strip wraps, not where the pointer may place it.
- Auto-resize stops at an 8pt glyph floor instead of collapsing, so a short Maximum Length cannot make the strip unreadable.
- Thumbnail cells now render with every space style. A native `NSGlassEffectView` inside a SwiftUI cell drew above the window capture and hid it, so thumbnail cells use SwiftUI glass and keep the capture visible.
- Screen Recording requests now open the System Settings pane when macOS will not show its prompt again, and Advanced offers a Relaunch button, because the grant only applies to a new process.
- The placement picker's footnote now describes each option accurately, including Neither, and notes that Settings and About still show a Dock icon while open.
- Tinted glass now carries the theme's accent colour through `NSGlassEffectView.tintColor` instead of tinting with the background colour. The tint sits on `glassTintedMaterial`, which is `clear` by default; the old fixed regular glass is no longer forced.
- The HUD's Liquid Glass now applies a private `NSGlassEffectView._variant` finish. Every style offers the full range 0...21 through `glassClearVariant` / `glassRegularVariant` / `glassTintedVariant` (defaults 11 / 5 / 2), with no curated names or hidden subsets. Opacity still applies on top. The glyph strip has the same three keys per style; `matchHUDAppearance` copies them.
- Glass opacity is no longer painted as a fill behind or over the effect. Liquid Glass samples the window backdrop, not sibling views, so a fill beneath it was invisible, and a fill above it washed the material out. The effect's own opacity now carries the value on both the HUD and the glyph strip.
- The glyph strip's glass now sits below the glyphs instead of hosting them as `contentView`, so its opacity and tint cannot fade the icons.
- The HUD's Liquid Glass now renders from an AppKit sibling below the SwiftUI grid, the same arrangement the Settings window and glyph strip use. A glass view nested in a SwiftUI `.background` only sampled the cells above it, so the panel around them stayed flat. The SwiftUI background draws only the border while native glass is active; the material comes from the selected style plus `glassTintedMaterial`. The effect's own opacity carries the slider value.
- The private glass finish is probed with `responds(to:)` and read back after setting, inside the 0…21 range AppKit accepts; when it is missing or does not stick, the view keeps its public style.
- Sbar glyphs now draw with the face from the same font file whose metadata supplied the codepoints. A newer user-installed font and the bundled font share one family name, so a family lookup could paint a different release's glyph for the same codepoint.
- Clear and regular use distinct fallback materials on pre-macOS 26 and under Reduce Transparency, where they used to be identical.
- The strip's neutral glass scrim follows the theme's light/dark background instead of the app appearance, so it matches the HUD for light themes on a dark system.
- The strip's solid fill uses the HUD's `background` role while `matchHUDAppearance` is on, and its own `cellBg` otherwise.
- The strip's hover highlight is no longer clipped 2pt short inside native glass.
- Reduce Transparency changes re-apply the strip and HUD backgrounds without waiting for the next refresh.
- A glass sub-type change rebuilds `NSGlassEffectView`, which caches its effect and does not repaint on `needsDisplay` alone.
- Selecting the strip's “Under Numbers” vertical layout no longer crashes: the stacked height no longer recurses through `contentHeight`.
- App-font glyphs stack centred under their space number. Centring now uses the glyph ink bounds rather than the advance box, whose asymmetric bearings left the visible glyph off-centre; native icons keep advance centring.
- The Notch Margin setting only appears for `leftOfNotch` and `rightOfNotch`, where it applies.
- `iconSpacing` now also sets the gap between stacked icon lines, and `indexPadding` separates the number from the first stacked icon, so vertical and horizontal layouts each read their spacing keys.
- Align HUD drag-and-drop hit rectangles with the grid instead of shifting every target down one row.
- Keep `recent` focus, space creation, and other yabai actions off the main thread.
- Wire the HUD panel into the drag monitor so custom-position HUDs can be dragged and their position persisted.
- Stop publishing an empty grid when a yabai query times out; serve the last good snapshot (bounded to 5s) instead.
- Preserve the socket nonce across listener restarts and re-register yabai signals after a rebuild; fail closed rather than registering nonce-less actions.
- Add single-instance protection and stop a second launch from unlinking the running instance's socket.
- Make "Restart Spacemap" wait for the old process to exit before reopening, and retain the relaunch helper.
- Keep a strong reference to `AppDelegate`; weak `NSApp.delegate` could otherwise leave the app running without lifecycle wiring.
- Prevent config crashes from huge finite numbers (`Int(Double)` traps) and clamp `cols`/`rows` to 1...32 so grid math cannot overflow.
- Stop a parse failure from overwriting the user's config with defaults; leave the file untouched and log the error even in silent mode.
- Make config self-heal converge by persisting clamped values once instead of rewriting the file on every load.
- Accept trailing commas, multi-line arrays, dotted keys, hex/underscored integers, and inline tables in TOML; round-trip U+2028/U+2029 and CR/CRLF files.
- Preserve direct `[spaceNames]` entries and migrate the legacy bare `glyphStrip = true` form.
- Serialize all config read-modify-write paths through `AppConfig.updateConfig`, including Settings, HUD/strip position, the font updater, and update mode.
- Cap config reads and backups instead of materializing an oversized file.
- Stop Settings saves from resetting `refuseUntrustedYabai` and disk-owned `appFont` state; surface save failures instead of silently succeeding.
- Repaint the glyph strip when its content changes even if its frame does not.
- Gate `NSGlassEffectView` on `compiler(>=6.2)` and Reduce Transparency everywhere so Swift 5.9/6.0 toolchains compile and accessibility settings are honoured.
- Stop treating text selection, sliders, and edge resizes as window drags; require a title-bar start or real window movement.
- Resolve drag targets by WindowServer owner PID and containing frame, and fall back to cached windows when the yabai snapshot arrives after mouse-up.
- Consume media keys and key-up events through the shared tap without double-firing, normalize the hardware fn flag for function keys, and treat `f1`/`fn+f1` as duplicate bindings.
- Pass all keys through while the hotkey recorder is active so bound media keys can be recorded.
- Log and retry drag-tap creation failures; remove the `passRetained` ownership model so monitors deinitialize.
- Clear hover and drag state when the tap is disabled, permission is revoked, or the HUD hides.
- Refresh cached Accessibility trust on a low-frequency poll and on tap-disabled events instead of querying TCC per keystroke.
- Stop rebuilding the entire HUD on every hovered-cell change; hover now only updates shared SwiftUI state.
- Reuse HUD panels across hide/show, create panels from `updateState`, and prefer the panel's own screen when saving custom positions.
- Avoid duplicate stacked panels for mirrored or stale displays.
- Skip ScreenCaptureKit captures during launch prewarm; capture lazily on first show and cancel/clear thumbnails when the style leaves thumbnails.
- Run Spotlight icon lookups concurrently with a 1.5s timeout and a negative cache instead of serializing behind one 5s process.
- Keep glyph-strip refreshes alive across settings changes by clearing the wedge latch and delivering canceled fetch completions.
- Apply space-name profile activation to the live inputs and glyph strip, flush pending edits before switching profiles, and notify an open Settings window.
- Rebuild the menu-bar profiles submenu when profiles change.
- Match hyphenated/underscored/compact theme names and reload `.smthemes` files when their mtime changes.
- Replace verbatim Settings strings with localized keys and expose glyph-strip VoiceOver segments.
- Keep manual update checks working with `updateMode = .off`; only automatic checks/downloads are disabled.
- Restore the previous activation policy after alerts so an open Settings window remains usable.
- Surface launch-at-login failures and treat `.requiresApproval` as pending rather than re-prompting every launch.
- Persist the move-to-Applications decline and compare path components instead of prefix-matching `/Applications`.
- Derive CLI/manpage symlink targets from `Bundle.main`, validate/quotes paths, and move the app via a staged atomic replace.
- Reject unknown CLI flags instead of launching a second daemon; use one version source for `--version` and About.
- Cap concurrent socket clients and queue bounded overflow instead of dropping commands after accepting them.
- Retry socket bind/listen failures with bounded backoff and expose the terminal failure state.
- Stop the nonce from rotating when another instance is live; rotate once per process otherwise.
- Store the config minimum OS in both the bundle and the appcast, and source Xcode versions from `VERSION`.
- Validate `make release` versions before writing any files, and regenerate the Xcode project after a version bump.
- Bound and safely abandon yabai pipe readers, keep space creation within a monotonic 20s budget, and guard mutable process checks with locks.
- Clear pending optimistic focus on a fresh fetch so a refresh cannot resurrect stale focus.
- Guard event-tap recovery with a generation counter and keep the drag delivery queue generation-safe.
- Add regression coverage for HUD geometry, config parsing/repair, socket nonce/liveness, drag evidence/fallbacks, hotkey routing, thumbnail policy, and appcast/version consistency.

## [1.1.1] - 2026-10-13

### Fixed
- Reject socket paths outside the per-user temp-dir allowlist before binding, failing closed on invalid input.
- Serialize Spotlight icon lookups on a dedicated queue so a wedged Spotlight cannot pin shared workers; mdfind now times out on a monotonic clock, reaps the child, drops stderr, caps output, and rejects quote/control chars in app names.
- Clear pending icon resolutions on cache clear so stale lookups cannot repopulate it.
- Document the sanitized socket username (non-alphanumerics stripped, empty falls back to uid) in the man page.

## [1.1.0] - 2026-10-09

### Added
- Optional always-visible glyph strip in the menu bar row, showing each yabai space's index plus a sketchybar-app-font glyph per window. A new **Glyph Strip** settings pane and `[glyphStrip]` config table control contents (`showSpaceNumbers`, `showLayoutSuffix`, `showAppIcons`, `dedupeAppsPerSpace`, `maxIconsPerSpace`), appearance (`iconSize`, `indexSize`, `iconSpacing`, `indexPadding`, `highlightCurrentSpace`, `backgroundMaterial`, `glassAmount`, `useThemeTint`, `shape`, `backgroundOpacity` solid-only 0.01...1.0, `cornerRadius`, `margin`, `yOffset`), decoration (`showDisplaySeparators`, `showAddSpaceButton`, `showPlaceholders`, `borderEnabled`, `theme`), click bindings (`leftClickAction`, `rightClickAction`, `middleClickAction`) and `position` (new `custom` value with `xOffset`). The former bare `[behavior] glyphStrip = true` boolean is still read and migrated on the next config repair.
- Space-name profiles: named sets of space names with an active index, edited in a dedicated Settings section and switchable from Settings or the menu bar. Out-of-range indexes repair to 0; an empty list repairs to Default.
- Session-only glyph-strip show/hide hotkey (`[behavior.glyphStripHotkey]`, default unbound). It flips an in-memory flag that starts visible every launch and is never written to config.
- `iconSource` glyph-strip option (`sbarFont` default vs `native`): native paints each app's own icon via `IconCache` at `iconSize` with sbar-glyph-then-initials fallback, picked in Settings → Glyph Strip → Icon Source or `[glyphStrip] iconSource`.

### Changed
- The glyph strip's palette is now theme-driven with no per-element colour keys: the current space, the add button and the hover highlight use the theme's `focused` role, resting glyphs use `text`, and the solid material fills with `cellBg`. Per-element colour keys (`currentSpaceColor`, `dimmedColor`, `indexColor`, `iconColor`, `hoverColor`, `backgroundColor`, `separatorColor`, `placeholderColor`, `addColor`) are removed; the legacy `backgroundStyle` key is migrated to `backgroundMaterial` + `shape` (none → none, pill → solid + pill, bar → solid + bar, roundedRect → solid + roundedRect, liquidGlass → liquidGlass + roundedRect).
- `yOffset` (default `0.0`, clamped -10...10): nudge the glyph strip vertically in screen-reading terms, so a positive value moves it down into the screen interior. Deliberately not clamped back into the menu bar row, since the panel is ordered at `.statusBar` level.
- Liquid glass now uses a continuous `glassAmount` slider (0...1, default 0.5) mirroring System Settings > Appearance > Liquid Glass — 0 is ultraclear, centre is default, 1 is opaque/tinted — driving the native glass `tintColor` alpha plus a fill overlay (view alpha stays 1.0). The old `glassStyle` key (`blurred`/`transparent`) still decodes to 0.5/0.15.
- `indexPadding` (default `6.0`, clamped 0...20): the gap between a space's index number and its first app glyph or placeholder. Distinct from `iconSpacing`, which tracks icons within a run and before `+N` overflow.
- Show gated controls only where they apply: the Glass Amount slider only for liquidGlass while Theme Tint is on, Background Opacity only for solid, Corner Radius only for roundedRect.
- Solid fills span the full panel height while the glass mask keeps a 2pt vertical inset; with material `none` the outline follows the selected shape, and shape `none` draws no outline even with the border on.
- Glyph verticals share one baseline with a 1pt drop; icon-font runs lift 1.5pt to sit with system digits, and the `+` add button draws bold at `indexSize + 2`.
- Clicks hit the full slot while the hover pill stays glyph-sized (symmetric `hoverPadding` growth on both axes).
- Preserved the `fn` modifier end to end (`maskSecondaryFn` record/serialize/match) across hotkeys and drop-focus modifiers.

### Removed
- Removed unused icon and thumbnail cache facade modules.
- Removed unused duplicate Settings and configuration owner types.
- Removed unused duplicate menu-bar owner types.

### Fixed
- Size the glyph strip's hover highlight to the glyphs it covers on both axes, and stop hover arming from anywhere in the 37.5pt menu bar row. The highlight is now the segment's glyph box grown by `hoverPadding` (default `1`, radius `4`) while clicks hit the full slot, so it sits on the glyphs rather than 1.5pt off and a few points too large.
- Draw every glyph segment at its own slot's horizontal position. Segment 0's first run was drawn 3pt right of its slot, and a segment with no runs spent no leading pad at all — the pad was applied per run — so every later segment drifted 3pt further left of the frame the panel sized itself from. The pen now spends the leading pad once per segment, before its runs.
- Honour `highlightCurrentSpace = false` for real. The flag only swapped the focused space's colour for the dimmed one, so the current space stayed visually distinct; it now resolves to byte-identical styling — colour, alpha and fill — so nothing marks it out, and hovering it behaves like hovering any other segment.
- Show spaces from every display on the one strip, in global-index order, matching the SketchyBar config this replaces (which set `ignore_association = true` for exactly this). Spaces are never renumbered per display and indexes are never assumed contiguous.
- Stop the glyph strip inventing spaces that do not exist. It iterated a fixed `1...maxSpaces` range, so every index past the last space yabai reported got a ghost segment. It now iterates the spaces yabai actually returned, which are global and not necessarily contiguous: real indexes are rendered in order, indexes that no longer exist are simply absent, display separators compare consecutive *rendered* spaces rather than `index + 1`, and click actions carry the real yabai index.
- Give adjacent app glyphs room to breathe with a new `iconSpacing` key (default `3.0`, clamped 0...20). The gap is applied between two app glyphs and before the `+N` overflow, and the panel measures its frame from the same gap array it draws with, so content cannot be clipped or leave a gap.
- Space the empty-space placeholder off the index with `indexPadding` and the `+N` overflow off the last icon with `iconSpacing`, so neither glues to its neighbour.
- Place the glyph strip beside the notch instead of inside it: `leftOfNotch` and `rightOfNotch` had their anchors inverted, so the strip started at the notch edge and extended into the camera housing. Both now anchor the strip's *outer* edge to the notch and are verified against the real notch geometry.
- Order the glyph strip front on every refresh instead of only after its panel already existed, so it is no longer created-but-never-shown until some later settings change.
- Track the glyph strip with an always-active tracking area, so hover and the hover pill work while Spacemap is not the active app.
- Anchor the glyph strip to the notch with `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` and a new `margin` key, instead of the far screen edges, and recompute on display and resolution changes.
- Honour each Material+Shape combo: `none` draws nothing, `solid` fills the strip with `cellBg` at `backgroundOpacity` (Settings slider 1...100%), and `liquidGlass` masks native glass to `shape` (`none` draws no shape; `pill`, `roundedRect` at `cornerRadius`, `bar`).
- Take the first click on the glyph strip without requiring Spacemap to be active, log failed yabai commands triggered from the strip instead of swallowing them, and report a font that exists but cannot be parsed.
- Drain yabai subprocess output without losing data when the system is under load.
- Time out every yabai command after 10s (SIGTERM then SIGKILL) and create the signal socket mode 0600 with non-blocking clients.
- Guard grid math at the boundaries: `cols > 0`, spaces clamped 0...16, zero-size display/cell frames return nil/empty instead of garbage.
- Clamp all glyph-strip numerics at the model boundary so a hand-edited TOML cannot produce a degenerate layout.
- Keep separate-display HUD cells aligned with their display-specific click and drag targets.
- Keep pinned HUD input state and focused-window drag fallback synchronized across refreshes.
- Keep window-drag event taps responsive and recover after macOS disables them.
- Resolve HUD themes once per render and keep application colors stable across launches.
- Release HUD and global-hotkey capture immediately when Accessibility is revoked, and let unrelated keys pass through pinned HUDs.
- Keep one owned pair of hotkey monitors, apply changed bindings without retaining old shortcuts, and trigger media shortcuts only on key-down.
- Apply update-mode and socket-health changes without requiring an app restart.
- Present and activate the real first-launch choices for login and update preferences.
- Preserve prior Sparkle appcast entries while replacing a duplicate current version.
- Preserve custom Settings values, coordinate hotkey recordings, restore window placement, and repair invalid configuration values.
- Reuse the owned About window instead of messaging an undefined app-delegate selector.
- Keep socket clients and yabai commands from blocking app input, shutdown, or state refreshes.
- Refresh full menu-bar previews for workspace topology changes and keep menu titles synchronized with hotkey changes.
- Package every localization with valid Unicode text, and reject release tags that disagree with the app version.
- Compare complete grid state instead of treating states with the same focused space as equal.
- Harden sketchybar-app-font discovery/update/install: direct bundle probes replace the tree walk, newer release tag wins, ATS auto-activation plus CoreText registration on launch/install, downloads gate on a real APPM payload, fresh-install checks compare the bundled release, cache drops on install and settings change.
- Match native icon sizing to the glyph advance it replaces so resolving an icon never reflows the strip; misses paint the sbar glyph or initials with 0.55 resting dim.
- Harden the glyph strip against freezes: debounced refresh with generation guard and re-entrant follow-up, font IO off-main, main-only icon fetch with background resolve plus one follow-up repaint, lock-guarded font/icon caches, silent drag persist.

<!-- pre-versioning -->

## [1.0.39] - 2026-08-15

### Fixed
- Let Settings record and match media-key hotkeys.
- Prevent duplicate normal and pinned HUD hotkey bindings.


## [1.0.38] - 2026-08-08

### Fixed
- Made the HUD's typed space number use the active theme's text color.

## [1.0.37] - 2026-08-08

### Changed
- Redesigned the README with a visual project overview, install guide, feature tour, configuration reference, and troubleshooting flow.

### Fixed
- Keep menu-bar workspace dots responsive by skipping unnecessary window-geometry queries.
- Release HUD keyboard capture and hide the HUD immediately when Accessibility permission is revoked.
- Made CI icon-preload tests independent of the runner's installed apps.


## [1.0.36] - 2026-08-08

### Fixed
- Restored Settings form layout and full window sizing instead of collapsed, unformatted content.

## [1.0.35] - 2026-08-08

### Fixed
- Prevented HUD cells from applying UI scale twice; restored centered sizing and HUD keyboard navigation wiring.
- Preserve one shared HUD controller across lifecycle, hotkey, menu bar, and deep-link paths.
- Keep Settings windows alive and activate the app when opening them.
- Restored HUD window-drag hover/drop handling and custom panel-position persistence.

### Changed
- Decomposed TOML parsing, thumbnail request/compositing, and HUD coordinate transforms behind focused modules.
- Removed unused composition modules, centralized menu-bar preview signal policy, and consolidated command-line tool operations.
- Split model declarations into configuration, theme, and yabai domain files.
- Refactored Config.swift from 685-line monolith to 36-line thin facade delegating to ConfigLoader/TOMLParser. Removed duplicated TOML lexer/serialization code and the duplicated hotkey() nested function.
- Added ConfigValuesProtocol, TOMLParserProtocol, and ConfigLoaderProtocol protocol interfaces for all config modules.
- Added protocol-based unit tests (ConfigFacadeTests) verifying Config facade delegation to ConfigLoader/TOMLParser.
- Added ConfigValues init(from: GridConfig) and ConfigLoader.save(_ config: GridConfig, to path:) for GridConfig ↔ ConfigValues conversion.

## [1.0.34] - 2026-08-07

### Added
- Added space jumps using number keys.

## [1.0.33] - 2026-08-05

### Changed
- Icon strips now order app icons by on-screen window position (left-to-right, then top-to-bottom) instead of yabai's raw window order.

## [1.0.32] - 2026-08-01

### Added
- Added optional number-key space jumps, including multi-digit space numbers and HUD feedback.
- Added Appearance setting to draw HUD panel shadow; default enabled.
- Added live yabai process and socket diagnostics to Advanced settings.
- Added a `spacemap(1)` manual page generated with scdoc and linked automatically alongside the CLI.

### Fixed
- Adaptive menu-bar workspace dots now keep refreshing after space changes.

## [1.0.31] - 2026-07-30

### Fixed
- The About window License tab now gives its scrollable MIT License text a stable visible layout.

## [1.0.30] - 2026-07-30

### Fixed
- Background-only app records with no Accessibility window reference are no longer treated as visible windows merely because their owner is a regular macOS app.

## [1.0.29] - 2026-07-30

### Fixed
- Icon strips now retain floating and extra windows accepted by the same display filter used by rectangle and hybrid views.

## [1.0.28] - 2026-07-30

### Added
- Added a polished Finder DMG with a gray-and-black grid background, installation instructions, and a drag-to-Applications arrow.
- Added a native About Spacemap window with app identity, version, copyright, Help, and Check for Updates actions.
- Added macOS 26 adaptive app-icon support while retaining the legacy `.icns` fallback.

### Changed
- Changed the app bundle and URL-scheme identifiers from `com.jsheffie.spacemap` to `com.zm.spacemap` for the independently maintained fork.
- Capitalized the packaged executable as `Spacemap` while retaining lowercase `spacemap` for the command-line symlink.
- Moved About Spacemap above Settings and redesigned its native window with About, Contributors, License, and Software Used tabs.

### Fixed
- Fixed release builds using the previous Git tag instead of the version declared in `VERSION`.

## [1.0.27] - 2026-07-29

### Fixed
- Keyboard input is released immediately if Accessibility permission is revoked while the HUD is visible.

## [1.0.26] - 2026-07-29

### Changed
- The visible HUD now consumes keyboard input after handling its own navigation and Settings shortcuts, preventing keystrokes from reaching other apps.

## [1.0.25] - 2026-07-29

### Changed
- Enlarged menu-bar workspace dots and let wide grid layouts use more horizontal space for legibility.

## [1.0.24] - 2026-07-29

### Changed
- Expanded focus-after-window-drop behavior to Never, Always, or While Holding Modifier, with Command, Fn, Option, Control, and Shift choices.

## [1.0.23] - 2026-07-29

### Added
- Added configurable menu-bar workspace previews for the current space, nearby spaces, or every active space, using live yabai window geometry.
- Added a compact menu-bar dot-grid mode that mirrors the configured workspace layout and highlights the focused space.

### Changed
- Menu-bar preview settings now stay hidden while the menu-bar icon itself is disabled.
- The all-spaces menu-bar preview now renders every space at full size in one horizontal row.
- Miniature menu-bar windows now have visible separation between adjacent panes.

## [1.0.22] - 2026-07-29

### Changed
- Replaced the JSONC config with TOML-only configuration at `~/.config/spacemap/config.toml`.
- Organized TOML settings into the same Grid, Space Names, Appearance, Behavior, and Advanced sections used by Settings.
- Removed obsolete config aliases, older-yabai classification compatibility, redundant macOS 13 availability branches, and stale config decoding infrastructure.

## [1.0.21] - 2026-07-29

### Added
- Added an off-by-default setting to show the HUD automatically whenever yabai changes spaces.
- Added `spacemap --space <selector>` for power-user and skhd navigation that focuses yabai spaces and shows the HUD, supporting indices 1–16, directional selectors, and labels.

### Fixed
- Yabai space-change signals now use macOS's system netcat so Homebrew netcat installations cannot break HUD updates.
- Exit-only CLI commands now run before AppKit startup, and `--trigger` toggles the existing HUD through its socket instead of launching a transient second HUD.


## [1.0.20] - 2026-07-29

### Added
- Added a Hybrid cell style that preserves rectangle rendering while centering a larger, proportionally scaled app icon in every window rectangle.

### Changed
- Moved space-number labels closer to the top-left while preserving proportional insets across HUD sizes.
- Moved Show Extra Windows into Debug/Advanced settings while preserving its explanatory help text.

### Fixed
- Hybrid cells, icon strips, and thumbnails now combine yabai window metadata with cached macOS app activation policy, retaining regular app windows even when AX fields disappear while Show Extra Windows controls utility/background records.
- Global hotkeys now recover without an app restart after Accessibility permission changes, event-tap invalidation, system disablement, or delayed tap creation.


## [1.0.19] - 2026-07-29

### Changed
- Thumbnail cell style now refreshes every visible space when the HUD opens instead of updating only the focused space after navigation.
- Thumbnail capture now renders directly at the cell's backing resolution, limits concurrent window captures, and debounces duplicate refresh events.
- Thumbnail cells observe atomic cache updates directly instead of rebuilding HUD panels, and each cell draws its thumbnail only once.
- Icon-style cells now render every yabai window, use yabai geometry for correct spatial placement, give one window the full cell, and divide two-window layouts into exact spatial halves.

### Fixed
- Thumbnail captures now exclude the Spacemap HUD and deterministically compose each space from its own yabai windows.
- Startup prewarming and atomic full-cache generations prevent mismatched, partially loaded, or stale space thumbnails.
- Thumbnail capture now rejects yabai's non-accessible helper-window records while including unmanaged on-screen overlays such as Raycast on the currently visible space.
- Space-number labels now keep a consistent scaled inset from cell edges at every HUD size.

## [1.0.18] - 2026-07-27

### Fixed
- Deep-link parsing now handles opaque `spacemap:action` URLs consistently across supported macOS versions.


## [1.0.17] - 2026-07-27

### Added
- Added `spacemap://` deep links for toggling or pinning the HUD, opening Settings or the menu-bar menu, and revealing the config file or themes folder.

## [1.0.16] - 2026-07-25

### Added
- Added an optional pinned HUD hotkey that toggles a permanently visible HUD independently of the normal timed hotkey.
- First-launch CLI installation now creates `/usr/local/bin` when possible and offers an explicit administrator-authorized fallback when macOS protects that location.
- Repository security policy documenting supported versions, vulnerability reporting, and expected disclosure handling.
- Repository support policy documenting where to ask for help and what information to include.
- Dropping a window onto an empty grid slot now creates any missing yabai spaces before moving the window there.

### Changed
- Settings sidebar categories now have roomier vertical spacing and larger click targets.
- Menu bar actions now use native SF Symbols for faster visual scanning, including Settings, CLI installation, updates, restart, permissions, and Quit.
- Settings category headings and sidebar labels now use larger, more prominent typography.
- Clarified the SwiftPM ignore guidance so `Package.resolved` is no longer presented as an ignored file in this repository.
- The canonical config file is now `~/.config/spacemap/spacemap.jsonc`; existing `config` files migrate automatically.
- Config loading now supports schema-backed JSON with JSONC comments, while still accepting legacy `key=value` files during migration.
- Hotkey parsing and triggering now support common media keys such as play/pause, next, previous, mute, volume, and brightness.
- Hotkey recorder now uses a more native inline control with a clear button to disable the current binding.
- Hotkey recorder now captures media keys directly and presents the selected binding in a native-style inline control.
- Settings window styling now leans more on native form chrome, lighter headers, and system background treatment.
- Settings view now uses segmented controls for small choice sets and tighter native-style footnote helpers.
- Settings window now uses a System Settings-style sidebar to group controls by section.
- Behavior settings can now optionally focus a destination space after a window is dropped there; the option defaults to off.
- Settings sidebar is now permanently visible, highlights the selected category, and uses full-row category buttons that reliably navigate the settings form.
- Each settings sidebar category now opens a distinct detail view instead of scrolling through one continuous form.
- User, contributor, developer, support, reference, roadmap, and agent documentation now describe the category-based Settings interface consistently.
- Moved the Command-Line Tool installer below the permission shortcuts in the menu-bar menu.

### Fixed
- CLI installation now validates its destination and never removes an unrelated file or symlink at `/usr/local/bin/spacemap`.
- JSON/JSONC config self-healing now runs on every load and preserves valid fields while repairing missing, mistyped, or out-of-range values.
- Hotkey recording now captures events delivered to the active Settings window and cleans up event monitors when the recorder disappears.


## [1.0.15] - 2026-07-25

### Fixed
- Release builds now ad-hoc sign and strictly verify every app bundle when a Developer ID certificate is unavailable, keeping Sparkle updates installable.

## [1.0.14] - 2026-07-25

### Added
- Configurable multi-monitor HUD modes: per-display overlays or a unified display map.
- Unified-grid visibility preference for showing the complete grid on the active display or every display.
- Separate-HUD visibility preference for showing all displays or only the display with yabai's focused space.
- Keyboard-navigation display wrapping preference: stay within the focused display or wrap across displays.

### Fixed
- Cross-display navigation now leaves a display at its grid-wrap edge instead of cycling through that display's spaces.
- Release automation now verifies the Sparkle public/private key pair before signing, preventing improperly signed updates from being published.
- Startup now warns when macOS “Displays have separate Spaces” is disabled.
- HUD reuses a prewarmed grid snapshot so active-space highlighting and app icons appear with the panel instead of a moment later.

### Changed
- Shifted in-cell space numbers slightly inward for more comfortable padding from the top-left edge.


## [1.0.13] - 2026-07-25

### Added
- `ConfigReader.keyCodeToSymbolicString(_:)` helper for keyCode→symbolic string conversion
- `ConfigReader.hotkeyToString(keyCode:modifiers:)` overload for raw keyCode/modifier encoding

### Changed
- `navigateSpace` now respects visible cells (active showMode, 16-space cap) instead of raw indices
- `ThemeManager.hex()` is now `static`
- `SettingsView.hotkeyStringFrom()` delegates to `ConfigReader.hotkeyToString()` (code dedup)
- `isMRUSpacesEnabled` check deferred to background queue so it no longer blocks startup
- yabai alert informative text now includes GitHub link

### Fixed
- Keyboard space navigation now skips empty placeholder cells, wraps correctly in incomplete rows and columns, and updates the HUD optimistically while focus changes are pending.
- `isYabaiRunning()` cache protected with `NSLock` to prevent data races
- `SettingsWindowController` no longer uses deprecated `setFrameUsingName`/`setFrameAutosaveName` pair
- `findBestGridLayoutIndexFor` dead conditional `layouts.isEmpty ? 0 : 0` simplified to `0`
- `ThumbnailCache` captures at 1x display size instead of 2x (perf/memory)
- `CellView` computed `filteredWindows` once instead of calling `windowFilter` twice per render
- `LAUNCH_AT_LOGIN` removed from SettingsView config save (handled by ServiceManagement, not file)


## [1.0.12] - 2026-07-25

### Fixed
- Release artifacts are built in the GitHub Actions workspace so they are available to the GitHub Release upload action.

## [1.0.11] - 2026-07-25

### Added
- `make release RELEASE=x.y.z` target for one-command releases
- `scripts/generate-changelog.sh` auto-moves `[Unreleased]` to versioned entry on release
- CHANGELOG gate in `make release` ensures entries exist before tagging
- Release checklist in DesignDocs/AGENTS.md
- `VERSION` file as fallback for version derivation

### Changed
- Revised installation guidance and refreshed the project icon in the README.

### Fixed
- Sparkle updater double-start bug — `updater.start()` replaced with idempotent `startUpdater()`
- Sparkle `sign_update` download URL updated to Sparkle 2.9.4 (2.7.1 was 404)
- SettingsView redundant config saves on every mode change
- Empty version strings in Info.plist when git tags missing
- VERSION derivation falls back to Info.plist when no tags or VERSION file exist


## [1.0.10] - 2026-07-24

### Changed
- Renamed the application and bundle consistently to `Spacemap` / `Spacemap.app` across the app, installer, documentation, and release workflow.

### Fixed
- Release automation now uses stable build-cache paths and publishes appcasts with the correct repository URL and app-bundle capitalization.


## [1.0.9] - 2026-07-24

### Added
- Sparkle automatic-update support, including update preferences and manual “Check for Updates” controls.
- Appcast publishing as part of the GitHub release workflow.

### Changed
- First-launch prompts now appear in a clearer order: yabai, Applications folder, launch at login, then updates.

### Fixed
- Sparkle is embedded and loaded correctly, with working framework rpaths, signing, feed URLs, and appcast generation.


## [1.0.8] - 2026-07-24

### Fixed
- The app returns to its background-only activation policy after the Settings window closes, preventing a lingering Dock icon.


## [1.0.7] - 2026-07-23

### Fixed
- Icon strips now scale to fit their cells instead of overflowing when many apps are visible.


## [1.0.6] - 2026-07-21

### Fixed
- **Auto-version from git tag**: Makefile now derives `VERSION` from `git describe --tags --abbrev=0` automatically. Info.plist version is replaced at build time regardless of current value. Release flow: `git tag v1.0.6 && git push`

---

## [1.0.5] - 2026-07-21

### Added
- **Show Extra Windows toggle**: `SHOW_EXTRA_WINDOWS` config option to display utility/floating windows (sublayer=normal). Default off — only shows sublayer=below windows
- **Custom HUD position memory**: Custom HUD positions now persist correctly when switching between presets (Center/Top/Bottom/Custom). Last dragged position stored in `CUSTOM_HUD_X`/`CUSTOM_HUD_Y`
- **Simplified HUD_POSITION config**: Now writes `HUD_POSITION=custom` instead of `HUD_POSITION=x,y` for cleaner config. Custom coordinates stored in separate `CUSTOM_HUD_X`/`CUSTOM_HUD_Y` keys
- **Debug/Advanced settings section**: Socket Health Interval moved to a new Debug/Advanced section at the bottom of Settings
- **on/off boolean values**: Config now writes `on`/`off` for boolean values (was `true`/`false`). Parsing accepts all: `true`, `false`, `1`, `0`, `yes`, `no`, `on`, `off`

### Changed
- **Settings UI reorder**: Behavior section reordered to: Hotkey → HUD Position → Auto-hide Timeout → Navigate with Arrow Keys → Navigate with Vim Keys → Hide Menu Bar Icon → Socket Health Interval (Debug/Advanced)
- **Space Names section moved**: Now appears directly below Grid section with proper title header
- **Auto-hide timeout display**: Label format changed to "Auto-hide Timeout (s) (0 = disabled): [value] [+/-]" with aligned mechanism
- **Grid layout label fix**: Fixed typo showing "4×(r))" instead of "4×2"
- **Show Icon Per Window**: Renamed from "Show Each Window Icon"

---

## [1.0.4] - 2026-07-21

### Added
- Info.plist version injection from VERSION file at build time (all app targets)
- Merged FAQ into README, combined API_SUMMARY + CHEAT_SHEET into REFERENCE.md

---

## [1.0.3] - 2026-07-20

### Added
- **Settings normalization**: UI_SCALE and ICON_SCALE normalized to 0.0–1.0; effective scale mapping in GridView (`0.5 + uiScale × 3.5` for UI, `0.2 + iconScale × 0.8` for icons)
- **CI DMG architecture verification**: Release workflow mounts each DMG and checks `lipo -archs`
- **Rendering math tests**: 8 unit tests for scale mapping (min/max/midpoint/monotonicity)

### Fixed
- CustomStepper `currentIndex` fallback uses closest match instead of 0 on floating-point mismatch
- Default config values updated: `uiScale: 0.5`, `iconScale: 0.5` (midpoint)
- UI_SCALE and ICON_SCALE validation now accepts 0.0–1.0

---

## [1.0.2] - 2026-07-18

### Fixed
- DMG app name unified: all arch DMGs contain `Spacemap.app` regardless of architecture
- Release workflow calls `make _dmg` directly instead of depending on intermediate targets

---

## [1.0.1] - 2026-07-17

### Added
- **Config backup**: Backs up to `.bak` before any config overwrite (self-heal or first-load normalize)
- **i18n localization**: 14 languages (en, es, de, it, fr, zh-Hans, hi, ar, pt, bn, ru, ja, ko, tr)
- **Homebrew tap**: `wiggly-sheets/homebrew-spacemap` with arch-conditional cask, auto-updated on release
- **F13-F20 hotkeys + Hyper/Capslock/Fn modifiers**: Full keyboard support in config parser

### Fixed
- HUD dual-layering: `show()` tears down orphaned panel; `refreshState()` guards on `isVisible`
- Launch at Login menu item matching uses `tag: 1001` instead of string comparison (localization-safe)

---

## [1.0.0] - 2026-01-19

### Added
- Space naming system with dynamic configuration in settings window
- Settings window with scrollable, resizable UI
- Hotkey recorder with global keyboard capture
- Launch at login toggle with state indicator
- Config file self-healing (auto-generates missing keys)
- CLI options: `--version`, `--help`, `--config`, `--trigger`, `--show-menu`, `--settings`
- Live auto-hide timeout with configurable delay
- Hotkey rapid-press protection (`isToggling` guard)
- Symlink creation (`/usr/local/bin/spacemap`) at launch
- Active space live highlighting via polling
- **File-based theme system**: `.smthemes` files in `~/.config/spacemap/themes/`, editable text files with rect1/rect2/rect3 colors, auto-seeded on first launch
- **Grid-aware keyboard navigation**: Arrow keys and vim keys (hjkl) with row/column wrapping, configurable via `VIM_KEYS` and `ARROW_KEYS`
- **Dynamic yabai path**: Auto-detects ARM (`/opt/homebrew/bin/yabai`) or Intel (`/usr/local/bin/yabai`) via FileManager, fixes blank HUD when launched from Finder
- **Default macOS greyscale theme**: Light grey cells with blue accent, replaces old black default
- **Window rect color palettes**: Themes define 3 base rect colors (`rect1`/`rect2`/`rect3`), HSL variation for >3 windows per space
- **Open Config File / Open Themes Folder buttons**: In Settings Appearance section
- **Icon caching**: `IconCache` singleton avoids re-fetching `NSWorkspace.shared.icon(forFile:)` on every render
- **Show Each Window Icon toggle**: `SHOW_MULTI_APP_ICONS` config option to show one icon per window or one per unique app in icon strip
- **Thumbnail cell style**: ScreenCaptureKit-based per-space capture, cached per cell index (macOS 14+)
- **Show Icon Strip toggle**: Config option `SHOW_ICON_STRIP` to show/hide app icon strip in cells
- **Show Space Numbers toggle**: Config option `SHOW_SPACE_NUMBERS` to show/hide space numbers
- **Show Space Names toggle**: Config option `SHOW_SPACE_NAMES` to show/hide custom space names
- **Hide Menu Bar Icon toggle**: Config option `HIDE_MENUBAR_ICON` to run headless
- **Cell opacity / inactive dimming**: Inactive spaces dimmed in the grid
- **MRU Spaces detection**: Warns user on launch if macOS MRU spaces is enabled, offers to disable
- **Screen Recording permissions link**: Added to menubar menu for easy access
- **Menubar hotkey symbols**: Show configured hotkey symbols in Show/Hide Map menu item
- **Menubar restart shortcut**: Cmd+R to restart Spacemap from menubar
- **Settings window hotkey recorder**: Global keyboard capture for setting hotkey in settings UI
- **Settings window space name editor**: Per-space text inputs in settings UI
- **Xcode project**: Generated from SPM via `scripts/generate-xcodeproj.py`, 4 targets (default, arm64, x86_64, universal)
- **Unit test suite**: 103 tests across 5 files — hotkey parsing, config parsing, theme loading, model encoding, grid computation, cell view logic
- **GitHub Actions CI**: `ci.yml` runs `swift test` + `swift build` on push/PR (macOS-14)
- **GitHub Actions Release**: `release.yml` builds 3 DMG variants + `checksums.txt` on tag push
- **Dependabot**: Weekly GitHub Actions dependency updates
- **Architecture-specific builds**: `make build-arm64`, `make build-x86_64`, `make build-universal`, DMG variants

### Changed
- Settings window now scrollable with proper dimensions
- `ThemeMode.automatic` renamed to `.auto` for consistency
- Config serialization uses string names instead of rawValue numbers
- Cell styles (rects, icons, hybrid) now properly serialized
- Auto-hide timer now resets unconditionally on HUD show
- Config parser now handles BOM, CR/LF, and inline comments
- Refactored `CellStyle` from 5 cases to 3: `rects`, `icons`, `thumbnails` (removed `hybrid`; use `icons` + `SHOW_ICON_STRIP=true` instead)
- CellStyle `"icons"` in config now sets `showIconStrip=true` by default
- Improved yabai mandatory check with alert dialog
- Improved Accessibility permission flow with polling
- Extracted testable pure functions: `parseConfig()`, `parseThemeContent()`, `CellView.appColor()`, `CellView.uniqueIconWindows()`, `GridView.computeVisibleSpaceIndices()`, `GridView.computeIdealSize()`
- `AppTheme` now conforms to `Equatable`

### Fixed
- HUD staying visible during space changes
- Hotkey double-trigger on rapid presses
- Settings window opening at full size
- Auto-hide timeout not syncing after settings changes
- Space names UI text field focus preservation
- Yabai not running alert not appearing frontmost
- Spaces MRU warning not appearing on startup
- Window drag-and-drop coordinate system mismatch
- Settings window not receiving keyboard focus (activation policy now set to `.regular` temporarily)
- Space name input field focus preservation
- Theme file parsing: `dropTarget` key case-insensitive matching (custom `.smthemes` files were silently failing, always falling back to hardcoded themes)

---

## [0.2.0] - 2024-03-15

### Added
- Menubar status item for manual show/hide
- Configurable hotkey (default: Ctrl+Page Down)
- Video demo in README
- Homebrew cask distribution support

### Changed
- Updated README with installation instructions
- Improved hotkey configuration flow

---

## [0.1.0] - 2023-06-01

### Added
- Homebrew distribution via `jsheffie/tap`
- Initial public release
- Basic UI scaling support

### Changed
- Repository moved to `jsheffie/spacemap`

---

## [0.0.8] - 2023-03-20

### Added
- Improved README install instructions

### Changed
- Documentation updates

---

## [0.0.7] - 2023-02-15

### Added
- Hybrid cell style (rectangles + app icons)
- Enhanced README documentation

---

## [0.0.6] - 2023-01-20

### Added
- Click-to-change-workspace functionality

---

## [0.0.5] - 2023-01-10

### Added
- Background color and highlight fixes
- Reverted CELL_STYLE config (subsequent fix in 0.0.4)

### Fixed
- Cell visibility and highlight in icons mode
- Background color rendering

---

## [0.0.4] - 2022-12-15

### Added
- CELL_STYLE config option (rects vs icons)
- Icons support with hybrid mode

### Changed
- Cell rendering logic

---

## [0.0.3] - 2022-12-01

### Fixed
- Active cell highlight visibility behind window rects
- Colored outline contrast

---

## [0.0.2] - 2022-11-15

### Added
- Event-driven architecture with yabai signals
- Auto-hide timer reset on space change

### Fixed
- HUD getting stuck on a workspace

---

## [0.0.1] - 2022-11-01

### Added
- Initial commit
- Basic HUD grid overlay
- yabai workspace visualization
- App adaptation from existing sharing (github/intellij-plantuml-plugin)

- Glyph strip padding can be locked to one value for all sides (default) or split into horizontal and vertical padding; separate vertical padding now insets horizontal strips too. The strip can also run as a menu-bar item instead of a floating panel.
