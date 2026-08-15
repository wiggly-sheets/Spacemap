#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
CHANGELOG="CHANGELOG.md"
DATE=$(date +%Y-%m-%d)

if [ ! -f "$CHANGELOG" ]; then
  echo "ERROR: $CHANGELOG not found"
  exit 1
fi

UNRELEASED_LINE=$(grep -n '^## \[Unreleased\]' "$CHANGELOG" | head -1 | cut -d: -f1 || true)
if [ -z "$UNRELEASED_LINE" ]; then
  echo "ERROR: No ## [Unreleased] section in $CHANGELOG"
  exit 1
fi

CONTENT_START=$((UNRELEASED_LINE + 1))

NEXT_SECTION=$(awk "NR>$UNRELEASED_LINE && /^## \[/" "$CHANGELOG" | head -1 || true)
if [ -n "$NEXT_SECTION" ]; then
  NEXT_LINE=$(grep -n "^## \[" "$CHANGELOG" | awk -F: "NR>1{print \$1; exit}" || true)
  NEXT_LINE=$(tail -n +"$CONTENT_START" "$CHANGELOG" | grep -n '^## \[' | head -1 | cut -d: -f1 || true)
  if [ -n "$NEXT_LINE" ]; then
    NEXT_LINE=$((CONTENT_START + NEXT_LINE - 1))
  fi
else
  NEXT_LINE=""
fi

if [ -n "$NEXT_LINE" ]; then
  UNRELEASED_CONTENT=$(sed -n "${CONTENT_START},$((NEXT_LINE - 1))p" "$CHANGELOG" | sed '/^$/d')
else
  UNRELEASED_CONTENT=$(sed -n "${CONTENT_START},\$p" "$CHANGELOG" | sed '/^$/d')
fi

if [ -z "$UNRELEASED_CONTENT" ]; then
  echo "ERROR: ## [Unreleased] section is empty. Add changelog entries before releasing."
  exit 1
fi

sed -i '' "s/^## \[Unreleased\]/## [$VERSION] - $DATE/" "$CHANGELOG"

SEPARATOR_LINE=$(grep -n '^---$' "$CHANGELOG" | head -1 | cut -d: -f1)
if [ -n "$SEPARATOR_LINE" ]; then
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
