#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
CHANGELOG="CHANGELOG.md"
DATE=$(date +%Y-%m-%d)

if [ ! -f "$CHANGELOG" ]; then
  echo "ERROR: $CHANGELOG not found"
  exit 1
fi

# Check if Unreleased section exists and has content (beyond the header)
UNRELEASED_LINE=$(grep -n '^## \[Unreleased\]' "$CHANGELOG" | head -1 | cut -d: -f1 || true)
if [ -z "$UNRELEASED_LINE" ]; then
  echo "ERROR: No ## [Unreleased] section in $CHANGELOG"
  exit 1
fi

# Find the content area after [Unreleased] header
CONTENT_START=$((UNRELEASED_LINE + 1))

# Find the next ## header (end of unreleased section)
NEXT_SECTION=$(awk "NR>$UNRELEASED_LINE && /^## \[/" "$CHANGELOG" | head -1 || true)
if [ -n "$NEXT_SECTION" ]; then
  NEXT_LINE=$(grep -n "^## \[" "$CHANGELOG" | awk -F: "NR>1{print \$1; exit}" || true)
  # Use the second ## [ occurrence after unreleased
  NEXT_LINE=$(tail -n +"$CONTENT_START" "$CHANGELOG" | grep -n '^## \[' | head -1 | cut -d: -f1 || true)
  if [ -n "$NEXT_LINE" ]; then
    NEXT_LINE=$((CONTENT_START + NEXT_LINE - 1))
  fi
else
  NEXT_LINE=""
fi

# Extract unreleased content (between header and next section)
if [ -n "$NEXT_LINE" ]; then
  UNRELEASED_CONTENT=$(sed -n "${CONTENT_START},$((NEXT_LINE - 1))p" "$CHANGELOG" | sed '/^$/d')
else
  UNRELEASED_CONTENT=$(sed -n "${CONTENT_START},\$p" "$CHANGELOG" | sed '/^$/d')
fi

if [ -z "$UNRELEASED_CONTENT" ]; then
  echo "ERROR: ## [Unreleased] section is empty. Add changelog entries before releasing."
  exit 1
fi

# Replace ## [Unreleased] header with versioned header
sed -i '' "s/^## \[Unreleased\]/## [$VERSION] - $DATE/" "$CHANGELOG"

# Add a fresh empty ## [Unreleased] section right after the format header
# Find the --- separator and insert after it
SEPARATOR_LINE=$(grep -n '^---$' "$CHANGELOG" | head -1 | cut -d: -f1)
if [ -n "$SEPARATOR_LINE" ]; then
  # Insert empty [Unreleased] section after the ---
  sed -i '' "${SEPARATOR_LINE}a\\
\\
## [Unreleased]\\
" "$CHANGELOG"
fi

echo "Moved Unreleased → [$VERSION] - $DATE"
echo ""
echo "Preview:"
echo ""
grep -A 20 "^## \[$VERSION\]" "$CHANGELOG" | head -25
