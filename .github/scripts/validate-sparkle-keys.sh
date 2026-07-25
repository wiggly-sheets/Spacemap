#!/usr/bin/env bash
set -euo pipefail

: "${SPARKLE_PUBLIC_KEY:?SPARKLE_PUBLIC_KEY is required}"
: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY is required}"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# Sparkle's CI private-key secret is the base64-encoded 32-byte Ed25519 seed.
# Build a minimal PKCS#8 key from that seed, then derive its public key with
# OpenSSL. This prevents publishing an app whose embedded public key cannot
# verify the signature made by the private-key secret.
private_seed="$work_dir/private-seed"
printf '%s' "$SPARKLE_PRIVATE_KEY" | tr -d '\r\n' | base64 -D > "$private_seed"

if [ "$(wc -c < "$private_seed" | tr -d ' ')" != "32" ]; then
    echo "::error::SPARKLE_PRIVATE_KEY must decode to a 32-byte Ed25519 seed."
    exit 1
fi

private_der="$work_dir/private.der"
printf '302e020100300506032b657004220420' | xxd -r -p > "$private_der"
cat "$private_seed" >> "$private_der"

derived_public="$({ openssl pkey -inform DER -in "$private_der" -pubout -outform DER | tail -c 32 | base64; } | tr -d '\r\n')"
expected_public="$(printf '%s' "$SPARKLE_PUBLIC_KEY" | tr -d '\r\n')"

if [ "$derived_public" != "$expected_public" ]; then
    echo "::error::SPARKLE_PRIVATE_KEY does not match SPARKLE_PUBLIC_KEY."
    exit 1
fi

echo "Sparkle signing key pair verified."
