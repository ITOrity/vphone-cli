#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rmdir "$tmpdir" 2>/dev/null || true' EXIT

payload="\$(shell touch $tmpdir/make-expansion-marker)"
make -C "$ROOT" -n setup_tools "VARIANT=$payload" >/dev/null 2>&1 || true

if [[ -e "$tmpdir/make-expansion-marker" ]]; then
    echo "make expanded VARIANT as executable make syntax" >&2
    exit 1
fi

echo "makefile safety checks passed"
