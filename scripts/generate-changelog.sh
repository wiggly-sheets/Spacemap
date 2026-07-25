#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
CHANGELOG="CHANGELOG.md"
DATE=$(date +%Y-%m-%d)

# Find last tag
LAST_TAG=$(git tag --sort=-v:refname 2>/dev/null | head -1 || true)
if [ -z "$LAST_TAG" ]; then
  echo "No previous tags found — cannot generate changelog"
  exit 1
fi

# Get file changes since last tag
CHANGES=$(git diff --name-status "$LAST_TAG"..HEAD 2>/dev/null || true)
if [ -z "$CHANGES" ]; then
  echo "No changes since $LAST_TAG"
  exit 0
fi

# Categorize changes
ADDED=""
CHANGED=""
REMOVED=""
DOCS=""
BUILD=""
CI=""

while IFS=$'\t' read -r status file; do
  case "$status" in
    A) label="New" ;;
    M) label="Modified" ;;
    D) label="Removed" ;;
    R*) label="Renamed" ;;
    *) label="Changed" ;;
  esac

  case "$file" in
    Sources/spacemap/*)
      name=$(basename "$file" .swift)
      case "$name" in
        App) entry="App entry point and lifecycle" ;;
        GridView) entry="Grid layout and container" ;;
        CellView) entry="Cell rendering" ;;
        HUDWindowController) entry="HUD window management" ;;
        YabaiClient) entry="Yabai integration" ;;
        ConfigReader) entry="Config file parsing" ;;
        HotkeyMonitor) entry="Global hotkey handling" ;;
        WindowDragHandler) entry="Window drag-and-drop" ;;
        SocketListener) entry="Unix socket listener" ;;
        ThumbnailCache) entry="Thumbnail capture cache" ;;
        IconCache) entry="App icon cache" ;;
        ThemeManager) entry="Theme system" ;;
        SettingsView) entry="Settings UI" ;;
        SettingsWindowController) entry="Settings window" ;;
        Models) entry="Data models" ;;
        *) entry="$name" ;;
      esac
      if [ "$status" = "A" ]; then
        ADDED="${ADGED:+$ADDED\n}- **Added:** $entry"
        [ -z "$ADDED" ] && ADDED="- **Added:** $entry"
      else
        CHANGED="${CHANGED:+$CHANGED\n}- **Changed:** $entry"
        [ -z "$CHANGED" ] && CHANGED="- **Changed:** $entry"
      fi
      ;;
    Sources/spacemap/Resources/*)
      lang=$(echo "$file" | grep -o '[a-z][a-z]\.lproj' | head -1 || true)
      if [ -n "$lang" ]; then
        lang_name="${lang/.lproj/}"
        CHANGED="${CHANGED:+$CHANGED\n}- **Changed:** Localization ($lang_name)"
        [ -z "$CHANGED" ] && CHANGED="- **Changed:** Localization ($lang_name)"
      fi
      ;;
    Tests/*)
      CHANGED="${CHANGED:+$CHANGED\n}- **Changed:** Unit tests"
      [ -z "$CHANGED" ] && CHANGED="- **Changed:** Unit tests"
      ;;
    AGENTS.md|DEVELOPER.md|CONTRIBUTING.md|REFERENCE.md)
      DOCS="${DOCS:+$DOCS\n}- **Changed:** $(basename "$file" .md) documentation"
      [ -z "$DOCS" ] && DOCS="- **Changed:** $(basename "$file" .md) documentation"
      ;;
    README.md)
      DOCS="${DOCS:+$DOCS\n}- **Changed:** User-facing documentation"
      [ -z "$DOCS" ] && DOCS="- **Changed:** User-facing documentation"
      ;;
    CHANGELOG.md) ;; # skip self
    Makefile)
      BUILD="${BUILD:+$BUILD\n}- **Changed:** Build system"
      [ -z "$BUILD" ] && BUILD="- **Changed:** Build system"
      ;;
    .github/workflows/*)
      CI="${CI:+$CI\n}- **Changed:** CI/CD pipeline"
      [ -z "$CI" ] && CI="- **Changed:** CI/CD pipeline"
      ;;
    .github/scripts/*)
      CI="${CI:+$CI\n}- **Changed:** Release scripts"
      [ -z "$CI" ] && CI="- **Changed:** Release scripts"
      ;;
    Package.swift|Package.resolved)
      BUILD="${BUILD:+$BUILD\n}- **Changed:** Swift package configuration"
      [ -z "$BUILD" ] && BUILD="- **Changed:** Swift package configuration"
      ;;
    VERSION) ;; # skip
    *.plist) ;; # skip Info.plist (handled in Sources)
    *)
      # Generic entry for other files
      name=$(basename "$file")
      CHANGED="${CHANGED:+$CHANGED\n}- **Changed:** $name"
      [ -z "$CHANGED" ] && CHANGED="- **Changed:** $name"
      ;;
  esac
done <<< "$CHANGES"

# Build entry sections
ENTRY=""
[ -n "$ADDED" ] && ENTRY="${ENTRY:+$ENTRY\n\n}### Added\n$ADDED"
[ -n "$CHANGED" ] && ENTRY="${ENTRY:+$ENTRY\n\n}### Changed\n$CHANGED"
[ -n "$REMOVED" ] && ENTRY="${ENTRY:+$ENTRY\n\n}### Removed\n$REMOVED"
[ -n "$DOCS" ] && ENTRY="${ENTRY:+$ENTRY\n\n}### Documentation\n$DOCS"
[ -n "$BUILD" ] && ENTRY="${ENTRY:+$ENTRY\n\n}### Build\n$BUILD"
[ -n "$CI" ] && ENTRY="${ENTRY:+$ENTRY\n\n}### CI/CD\n$CI"

if [ -z "$ENTRY" ]; then
  echo "No categorized changes found for v$VERSION"
  exit 0
fi

# Generate full entry
HEADER="## [$VERSION] - $DATE"
FULL_ENTRY="$HEADER\n\n$ENTRY"

# Prepend after the header section (after the first ---)
if [ -f "$CHANGELOG" ]; then
  TEMP=$(mktemp)
  # Find the line number of the first --- separator
  SEPARATOR_LINE=$(grep -n '^---$' "$CHANGELOG" | head -1 | cut -d: -f1)
  if [ -n "$SEPARATOR_LINE" ]; then
    head -"$SEPARATOR_LINE" "$CHANGELOG" > "$TEMP"
    echo "" >> "$TEMP"
    echo -e "$FULL_ENTRY" >> "$TEMP"
    echo "" >> "$TEMP"
    tail -n +$((SEPARATOR_LINE + 1)) "$CHANGELOG" >> "$TEMP"
  else
    echo -e "$FULL_ENTRY\n" > "$TEMP"
    cat "$CHANGELOG" >> "$TEMP"
  fi
  mv "$TEMP" "$CHANGELOG"
else
  echo -e "# Changelog\n\nAll notable changes to this project are documented in this file.\n\nThe format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),\nand this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).\n\n---\n\n$FULL_ENTRY" > "$CHANGELOG"
fi

echo "Generated changelog entry for v$VERSION"
echo ""
echo "Preview:"
echo ""
echo -e "$FULL_ENTRY"
