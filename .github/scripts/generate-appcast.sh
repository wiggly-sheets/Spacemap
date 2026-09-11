#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:?VERSION is required}"
DMG_FILE="${DMG_FILE:?DMG_FILE is required}"
DMG_SIZE="${DMG_SIZE:?DMG_SIZE is required}"
DMG_HASH="${DMG_HASH:-}"
ED_SIGNATURE="${ED_SIGNATURE:-}"
APP_NAME="${APP_NAME:-Spacemap}"
APPCAST_URL="${APPCAST_URL:-https://wiggly-sheets.github.io/Spacemap/appcast.xml}"
RELEASES_URL="${RELEASES_URL:-https://github.com/wiggly-sheets/Spacemap/releases/download/v${VERSION}}"
MAX_ITEMS="${MAX_ITEMS:-5}"
ALLOW_MISSING_APPCAST="${ALLOW_MISSING_APPCAST:-0}"

case "$MAX_ITEMS" in
    ''|*[!0-9]*|0)
        echo "MAX_ITEMS must be a positive integer" >&2
        exit 1
        ;;
esac

case "$ALLOW_MISSING_APPCAST" in
    0|1) ;;
    *)
        echo "ALLOW_MISSING_APPCAST must be 0 or 1" >&2
        exit 1
        ;;
esac

if ! command -v xmllint >/dev/null 2>&1; then
    echo "xmllint is required to validate appcast history" >&2
    exit 1
fi

SIGNATURE_ATTR=""
[ -n "$ED_SIGNATURE" ] && SIGNATURE_ATTR=" sparkle:edSignature=\"${ED_SIGNATURE}\""

NEW_ITEM=$(cat << ITEM_EOF
    <item>
      <title>Version ${VERSION}</title>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>https://github.com/wiggly-sheets/Spacemap/releases/tag/v${VERSION}</sparkle:releaseNotesLink>
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
    <link>${APPCAST_URL}</link>
    <description>Most recent changes with links to the binaries.</description>
    <language>en</language>
APPCAST_HEADER_EOF
}

generate_appcast_footer() {
    echo "  </channel>"
    echo "</rss>"
}

validate_appcast() {
    local appcast_path="$1"

    if ! xmllint --noout "$appcast_path" >/dev/null 2>&1; then
        echo "Appcast is not valid XML: ${appcast_path}" >&2
        return 1
    fi

    local is_valid
    is_valid=$(xmllint --xpath '
        boolean(
            count(/rss) = 1 and
            count(/rss/channel) = 1 and
            count(/rss/channel/item) > 0 and
            count(
                /rss/channel/item[
                    count(*[
                        local-name() = "version" and
                        namespace-uri() = "http://www.andymatuschak.org/xml-namespaces/sparkle"
                    ]) != 1 or
                    count(*[
                        local-name() = "shortVersionString" and
                        namespace-uri() = "http://www.andymatuschak.org/xml-namespaces/sparkle"
                    ]) != 1 or
                    count(enclosure) != 1
                ]
            ) = 0
        )
    ' "$appcast_path" 2>/dev/null || true)

    if [ "$is_valid" != "true" ]; then
        echo "Appcast does not contain a valid Sparkle item history: ${appcast_path}" >&2
        return 1
    fi
}

append_previous_items() {
    local existing_path="$1"
    local previous_item_limit=$((MAX_ITEMS - 1))
    [ "$previous_item_limit" -gt 0 ] || return

    local existing_item_count
    existing_item_count=$(xmllint --xpath 'count(/rss/channel/item)' "$existing_path")

    local item_index=1
    local appended_count=0
    while [ "$item_index" -le "$existing_item_count" ] && [ "$appended_count" -lt "$previous_item_limit" ]; do
        local item_version
        item_version=$(xmllint --xpath "string(/rss/channel/item[${item_index}]/*[
            local-name() = 'version' and
            namespace-uri() = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
        ])" "$existing_path")

        if [ "$item_version" != "$VERSION" ]; then
            xmllint --xpath "/rss/channel/item[${item_index}]" "$existing_path"
            echo
            appended_count=$((appended_count + 1))
        fi
        item_index=$((item_index + 1))
    done
}

generate_appcast() {
    local existing_path="${1:-}"

    generate_appcast_header
    echo "${NEW_ITEM}"
    if [ -n "$existing_path" ]; then
        append_previous_items "$existing_path"
    fi
    generate_appcast_footer
}

work_directory=$(mktemp -d "${TMPDIR:-/tmp}/spacemap-appcast.XXXXXX")
trap 'rm -rf "$work_directory"' EXIT
existing_appcast_path="${work_directory}/existing.xml"
generated_appcast_path="${work_directory}/generated.xml"

if curl -fL --silent --show-error --max-time 30 "$APPCAST_URL" --output "$existing_appcast_path"; then
    validate_appcast "$existing_appcast_path"
    generate_appcast "$existing_appcast_path" > "$generated_appcast_path"
elif [ "$ALLOW_MISSING_APPCAST" = "1" ]; then
    echo "Existing appcast is unavailable; generating an explicitly allowed first-release feed" >&2
    generate_appcast > "$generated_appcast_path"
else
    echo "Failed to fetch existing appcast; refusing to truncate release history" >&2
    exit 1
fi

validate_appcast "$generated_appcast_path"
mv "$generated_appcast_path" appcast.xml
echo "Generated appcast.xml with version ${VERSION}"
