#!/usr/bin/env zsh
set -euo pipefail

if [[ -z "${VPHONE_SIGNCERT:-}" ]]; then
    print -u2 "error: VPHONE_SIGNCERT must point to an external signing certificate"
    exit 1
fi

path="${VPHONE_SIGNCERT:A}"
if [[ ! -f "$path" || ! -r "$path" ]]; then
    print -u2 "error: VPHONE_SIGNCERT is not a readable regular file: $path"
    exit 1
fi

mode=""
mode="$(/usr/bin/stat -f '%Lp' "$path")"
case "$mode" in
    400|600|700) ;;
    *)
        print -u2 "error: VPHONE_SIGNCERT must be owner-only (mode 400, 600, or 700): $mode"
        exit 1
        ;;
esac

print -r -- "$path"
