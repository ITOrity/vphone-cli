#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

rg -q 'ARCHIVE_EXTRACT_SECURE_SYMLINKS' scripts/vphoned/unarchive.m || {
    echo "archive extraction is missing secure symlink protection" >&2
    exit 1
}

rg -q 'VPHONE_ALLOW_INSECURE_PACKAGES' scripts/vphone_jb_setup.sh scripts/fetch_debs.sh || {
    echo "unsigned package flow is missing an explicit opt-in" >&2
    exit 1
}

echo "package security checks passed"
