#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="${1:-$ROOT/scripts/resources/cfw_input.tar.zst}"

[[ -f "$ARCHIVE" ]] || {
    echo "storage archive is missing: $ARCHIVE" >&2
    exit 1
}

if tar --zstd -tf "$ARCHIVE" | rg -q '(^|/)signcert\.p12$'; then
    echo "storage archive still contains a signing credential" >&2
    exit 1
fi

echo "storage archive signing credential check passed"
