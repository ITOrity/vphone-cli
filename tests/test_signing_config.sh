#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[[ ! -e scripts/vphoned/signcert.p12 ]] || {
    echo "tracked signing credential still exists" >&2
    exit 1
}

rg -n 'scripts/vphoned/signcert\.p12|Resources/signcert\.p12' Makefile sources scripts \
    && {
        echo "build still references the bundled signing credential" >&2
        exit 1
    } || true

rg -n 'cfw_input/signcert\.p12' sources \
    && {
        echo "firmware patcher still references the archive signing credential" >&2
        exit 1
    } || true

rg -n 'VPHONE_SIGNCERT' Makefile sources scripts >/dev/null || {
    echo "external VPHONE_SIGNCERT boundary is missing" >&2
    exit 1
}

echo "signing configuration checks passed"
