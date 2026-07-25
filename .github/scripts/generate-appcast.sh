#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:?VERSION is required}"
DMG_FILE="${DMG_FILE:?DMG_FILE is required}"
DMG_SIZE="${DMG_SIZE:?DMG_SIZE is required}"
DMG_HASH="${DMG_HASH:-}"
ED_SIGNATURE="${ED_SIGNATURE:-}"
APP_NAME="${APP_NAME:-Spacemap}"
APPcast_URL="${APPcast_URL:-https://wiggly-sheets.github.io/spacemap/appcast.xml}"
RELEASES_URL="${RELEASES_URL:-https://github.com/wiggly-sheets/spacemap/releases/download/v${VERSION}}"
MAX_ITEMS="${MAX_ITEMS:-5}"

SIGNATURE_ATTR=""
[ -n "$ED_SIGNATURE" ] && SIGNATURE_ATTR=" sparkle:edSignature=\"${ED_SIGNATURE}\""

NEW_ITEM=$(cat << ITEM_EOF
    <item>
      <title>Version ${VERSION}</title>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>https://github.com/wiggly-sheets/spacemap/releases/tag/v${VERSION}</sparkle:releaseNotesLink>
      <enclosure url="${RELEASES_URL}/${DMG_FILE}"${SIGNATURE_ATTR} length="${DMG_SIZE}" type="application/octet-stream" sparkle:architecture="universal"/>
    </item>
ITEM_EOF
)

generate_appcast_header() {
    cat << APPCAST_HEADER_EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>${APP_NAME}</title>
    <link>${APPcast_URL}</link>
    <description>Most recent changes with links to the binaries.</description>
    <language>en</language>
APPCAST_HEADER_EOF
}

generate_appcast_footer() {
    echo "  </channel>"
    echo "</rss>"
}

generate_new_appcast() {
    generate_appcast_header
    echo "${NEW_ITEM}"
    generate_appcast_footer
}

fetch_existing_appcast() {
    local existing
    existing=$(curl -s --max-time 30 "${APPcast_URL}" 2>/dev/null || true)
    if [ -z "$existing" ]; then
        generate_new_appcast
        return
    fi

    generate_appcast_header

    echo "${NEW_ITEM}"

    local in_item=false
    local item_count=0
    local skip_footer=true

    while IFS= read -r line; do
        if $in_item; then
            if echo "$line" | grep -q '</item>'; then
                in_item=false
                item_count=$((item_count + 1))
                if [ "$item_count" -ge "$MAX_ITEMS" ]; then
                    break
                fi
                echo "$line"
            fi
        else
            if echo "$line" | grep -q '<item>'; then
                in_item=true
                echo "$line"
            elif echo "$line" | grep -q '</rss>'; then
                skip_footer=false
            fi
        fi
    done <<< "$(echo "$existing" | tail -n +2 | head -n -1)"

    generate_appcast_footer
}

generate_new_appcast > appcast.xml
echo "Generated appcast.xml with version ${VERSION}"