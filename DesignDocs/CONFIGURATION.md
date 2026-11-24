# Configuration

Spacemap reads `~/.config/spacemap/config.toml`. This page lists every key, its default and what it does. Back to the [README](../README.md).

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
showSpaceLayout = false          # layout letter next to index: float="f", stack="s", bsp="b" (strip uses bare for bsp); needs showSpaceNumbers
showIconStrip = true

[appearance]
theme = "default"
uiScale = 0.5
backgroundAlpha = 0.3       # shared opacity when matchBackgroundOpacity is on
backgroundStyle = "glass"   # glass, solid
glassStyle = "regular"      # clear | regular | tinted (glass only)
glassClearVariant = 11      # private glass finish per style, 0...21
glassRegularVariant = 5
glassTintedVariant = 2
glassTintedMaterial = "clear"   # clear | regular (under the tint)
glassClearOpacity = 0.15    # per-style opacity; used unless matching
glassRegularOpacity = 0.3
glassTintedOpacity = 0.3
spacesMatchBackground = true    # false gives cells their own layer
spacesBackgroundStyle = "glass" # none | solid | glass
spacesGlassStyle = "clear"      # clear | regular | tinted
spacesOpacity = 0.5
spacesCornerRadius = 4
solidOpacity = 1.0          # solid fill, no blur
matchBackgroundOpacity = false  # true = all styles share backgroundAlpha
hudShadow = true

[behavior]
autoHideTimeout = 5
jumpToSpaceEnabled = false
fuzzySpaceJumpEnabled = true # type a space name to jump; unbound letters only

[hudKeys]
left = ["h", "left"]          # every HUD action takes a list of hotkeys
right = ["l", "right"]
up = ["k", "up"]
down = ["j", "down"]
first = ["f"]                 # go to first space
last = ["e"]                  # go to last space
recent = ["r"]                # back to the previous space
close = ["escape", "c"]       # empty list = unbound
newSpace = ["a"]
newSpaceAndFocus = ["t"]
deleteSpace = ["w"]
layoutBSP = ["b"]
layoutStack = ["s"]
layoutFloat = ["u"]
cycleLayout = []              # cycle BSP -> stack -> float; empty list = unbound
moveSpaceBack = []            # move the focused space one slot left
moveSpaceForward = []         # move the focused space one slot right
previousSpace = ["p"]         # previous space, wrapping at the start
nextSpace = ["n"]             # next space, wrapping at the end

[behavior.hotkey]
keyKind = "keyCode"
keyCode = 49
modifiers = ["ctrl"]

[glyphStrip]
enabled = false
maxIconsPerSpace = 8         # 0 = unlimited
leftClickAction = "focusSpace"
rightClickAction = "destroySpace"
middleClickAction = "none"
position = "leftOfNotch"
```

Glyph strip reference — every key with its default:

```toml
[glyphStrip]
enabled = false                   # master toggle
showSpaceNumbers = true           # draw the space index digit
showLayoutSuffix = true           # layout letter: bsp="", float="f", stack="s"
showAppIcons = true               # draw sketchybar-app-font glyphs
dedupeAppsPerSpace = true         # one glyph per app per space; false = one per window
maxIconsPerSpace = 8              # glyph cap per space, then "+N"; 0 = unlimited
iconSize = 11.0                   # glyph point size, clamped 6...24
indexSize = 11.0                  # space-number point size, clamped 6...24
highlightCurrentSpace = true
backgroundMaterial = "none"       # none (Transparent) | solid | liquidGlass
glassStyle = "regular"            # liquidGlass only: clear | regular | tinted
glassClearVariant = 11            # finish per style, 0...21
glassRegularVariant = 5
glassTintedVariant = 2
glassTintedMaterial = "clear"
matchHUDAppearance = false        # true = copy HUD material, glass type, finish, opacity, theme
backgroundOpacity = 0.35          # shared opacity when matchBackgroundOpacity is on
matchBackgroundOpacity = false    # true = all strip styles share backgroundOpacity
glassClearOpacity = 0.35          # per-style glass backing opacity
glassRegularOpacity = 0.35
glassTintedOpacity = 0.35
solidOpacity = 0.35               # solid backing opacity, no blur
cornerRadius = 20.0               # shape: 0 = square ends, half the strip height or more = pill
margin = 6.0                      # gap to the notch edge, clamped 0...40
plainMargin = 6.0                 # gap to the screen edge on a display without a notch
iconSpacing = 3.0                  # extra gap between two app icons and before +N, clamped 0...20
indexPadding = 6.0                 # gap from the space number to its first icon or placeholder, clamped 0...20
hoverPadding = 1.0                # grow around the hovered segment's glyph box, both
padding = 4.0                     # all-side strip padding while lockPadding is true
                                  # axes (symmetric), clamped 0...12; hit-testing uses
                                  # the full slot while the pill stays glyph-sized
hoverCornerRadius = 4.0           # rounding of that hover highlight, clamped 0...20
showDisplaySeparators = true      # "|" between spaces on different displays
showAddSpaceButton = true         # trailing "+"
showPlaceholders = true           # placeholder glyph for empty spaces
leftClickAction = "focusSpace"    # none | focusSpace | destroySpace | moveWindowHere |
                                 # toggleFullscreen | floatWindow | balanceWindows | mergeWindows
rightClickAction = "destroySpace"
middleClickAction = "none"
position = "leftOfNotch"          # notched displays: leftOfNotch | rightOfNotch | center | custom
plainPosition = "center"          # displays without a notch: leftOfNotch = left edge,
                                  # center, rightOfNotch = right edge, custom
customX = 0.5                     # notched custom only; fraction of spare width, 0...1
customY = 0.5                     # notched custom only; fraction of spare height, 0 bottom, 1 top
customScreen = ""                 # notched custom only; display identity, empty = usual target
plainCustomX = 0.5                # plain custom only; fraction of spare width, 0...1
plainCustomY = 0.5                # plain custom only; fraction of spare height
plainCustomScreen = ""            # plain custom only; display identity
borderEnabled = true              # hairline outline, independent of the material;
                                  # with none it follows the corner radius
theme = ""                        # follow main HUD theme; or a theme name
                                    # On a notched display, leftOfNotch/rightOfNotch sit
                                    # BESIDE the notch: the strip's outer edge is anchored
                                    # `margin` short of NSScreen.auxiliaryTopLeftArea.maxX /
                                    # auxiliaryTopRightArea.minX, so it never overlaps the
                                    # camera housing. center puts the strip on the notch
                                    # midpoint, which is under the camera on most displays —
                                    # avoid it. A display without a notch uses
                                    # plainPosition/plainMargin instead, and defaults to
                                    # centre, so a notch preset never parks the strip against
                                    # the screen edge on a plain display. Custom X/Y and the
                                    # display identity are stored separately for each screen
                                    # type; Lock Position is one toggle for both.

```

<details>
<summary><b>Configuration reference</b></summary>

<br/>

| Table | Useful keys |
|---|---|
| `[grid]` | `cols`, `rows`, `maxSpaces`, `cellStyle`, `showMode`, `multiMonitorHUDMode`, `unifiedHUDVisibility`, `separateHUDVisibility`, `displayNavigationWrap`, `showSpaceNumbers`, `showSpaceLayout`, `showIconStrip`, `showMultiAppIcons`, `hudIconSource`, `hudIconStripSeparate`, `hudIconStripSource` |
| `[spaceNames]` | `showSpaceNames`; `namingMode` (`custom`, `auto`); `autoNameAppCount` (1-3); names live in `[spaceNames.names]` as quoted space-number keys; named sets live in `[spaceNameProfiles]`. In `auto` mode each space lists up to `autoNameAppCount` visible apps in reading order, joined by `·` |
| `[appearance]` | `theme`, `mode`, `backgroundAlpha`, `backgroundStyle`, `glassStyle`, `glassClearVariant`, `glassRegularVariant`, `glassTintedVariant`, `glassTintedMaterial`, `glassClearOpacity`, `glassRegularOpacity`, `glassTintedOpacity`, `solidOpacity`, `matchBackgroundOpacity`, `hudShadow`, `hudCornerRadius`, `hudFontName`, `hudFontSize`, `hudTextColor`, `spacesMatchBackground`, `spacesBackgroundStyle`, `spacesGlassStyle`, `spacesGlassClearVariant`, `spacesGlassRegularVariant`, `spacesGlassTintedVariant`, `spacesGlassTintedMaterial`, `spacesOpacity`, `spacesCornerRadius`, `uiScale`, `iconScale` |
| `[behavior]` | `autoHideTimeout`, `jumpToSpaceEnabled`, `fuzzySpaceJumpEnabled`, `focusSpaceOnWindowDrop`, `focusSpaceOnWindowDropModifier`, `showHUDOnSpaceChange`, `showHUDInteractionFeedback`, `spaceDropMode`, `spaceDragFocus`, `windowDragFocus`, `hudAnimationsEnabled`, `hudAnimationStyle`, `showBSPLayoutBadge`, `showStackLayoutBadge`, `showFloatLayoutBadge`, `showThumbnailWallpaper`, `presence`, `updateMode`, `glyphStripHotkey` (session-only strip toggle, default unbound) |
| `[behavior.hudPosition]` | `kind` (`center`, `top`, `bottom`, `custom`); custom adds `x`/`y` (0...1 spare-width/height fractions) and an optional `screen` display identity, written by dragging the HUD |
| `[hudKeys]` | one key per HUD action (`left`, `right`, `up`, `down`, `first`, `last`, `recent`, `close`, `newSpace`, `newSpaceAndFocus`, `deleteSpace`, `layoutBSP`, `layoutStack`, `layoutFloat`, `cycleLayout`, `moveSpaceBack`, `moveSpaceForward`, `previousSpace`, `nextSpace`), each a list of hotkeys; an empty list leaves the action unbound |
| `[glyphStrip]` | `enabled`, `theme`, `showSpaceNumbers`, `spaceLabelStyle`, `showLayoutSuffix`, `showAppIcons`, `dedupeAppsPerSpace`, `maxIconsPerSpace`, `iconSize`, `indexSize`, `iconSpacing`, `indexPadding`, `highlightCurrentSpace`, `backgroundMaterial`, `glassStyle`, `matchHUDAppearance`, `backgroundOpacity`, `matchBackgroundOpacity`, `glassClearVariant`, `glassRegularVariant`, `glassTintedVariant`, `glassTintedMaterial`, `glassClearOpacity`, `glassRegularOpacity`, `glassTintedOpacity`, `solidOpacity`, `cornerRadius`, `margin`, `plainMargin`, `padding`, `lockPadding`, `horizontalPadding`, `displayMode`, `hoverPadding`, `hoverCornerRadius`, `showDisplaySeparators`, `showAddSpaceButton`, `showPlaceholders`, `leftClickAction`, `rightClickAction`, `middleClickAction`, `position`, `plainPosition`, `orientation`, `verticalLayout`, `customX`, `customY`, `customScreen`, `plainCustomX`, `plainCustomY`, `plainCustomScreen`, `lockPosition`, `borderEnabled` |
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
