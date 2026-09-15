#!/bin/zsh
# fetch_debs.sh — Download debs from a URL manifest into a cache dir.
# Skips files already cached; leaves manually-added debs alone. A failed
# download is reported and skipped, never fatal (always exits 0).
#
# Usage: fetch_debs.sh [cache_dir] [manifest_file]
#   defaults: <repo>/debs and <repo>/debs.list

set -uo pipefail

[[ -n "${_VPHONE_PATH:-}" ]] && export PATH="$_VPHONE_PATH"

SCRIPT_DIR="${0:a:h}"
REPO_ROOT="${SCRIPT_DIR:h}"

# VPHONE_DEBS_DIR (set by the app to a writable ~/.vphone/debs) keeps the cache
# out of the read-only .app bundle; the manifest is bundled next to this script's
# repo/Resources root, so $REPO_ROOT/debs.list resolves in both dev and .app.
CACHE_DIR="${1:-${VPHONE_DEBS_DIR:-$REPO_ROOT/debs}}"
MANIFEST="${2:-$REPO_ROOT/debs.list}"
ALLOW_INSECURE_PACKAGES="${VPHONE_ALLOW_INSECURE_PACKAGES:-0}"
HASH_MANIFEST="${VPHONE_DEBS_HASH_MANIFEST:-${MANIFEST}.sha256}"

verify_deb() {
    local name="$1" path="$2" expected actual
    [[ "$ALLOW_INSECURE_PACKAGES" == "1" ]] && return 0
    [[ -f "$HASH_MANIFEST" ]] || {
        echo "  [!] ERROR: refusing unverified package; missing hash manifest: $HASH_MANIFEST" >&2
        return 1
    }
    expected="$(awk -v wanted="$name" '$2 == wanted { print $1; exit }' "$HASH_MANIFEST")"
    if ! print -r -- "$expected" | /usr/bin/grep -Eq '^[0-9a-fA-F]{64}$'; then
        echo "  [!] ERROR: no SHA-256 entry for $name in $HASH_MANIFEST" >&2
        return 1
    fi
    actual="$(/usr/bin/shasum -a 256 "$path" | awk '{ print $1 }')"
    [[ "$actual" == "$expected" ]] || {
        echo "  [!] ERROR: SHA-256 mismatch for $name" >&2
        return 1
    }
}

mkdir -p "$CACHE_DIR"

if [[ "$ALLOW_INSECURE_PACKAGES" != "1" && ! -f "$HASH_MANIFEST" ]]; then
    echo "  [!] ERROR: refusing package downloads without SHA-256 manifest: $HASH_MANIFEST" >&2
    exit 1
fi

deb_filename_from_url() {
    local url="$1"
    url="${url%%\#*}"
    url="${url%%\?*}"
    print -r -- "${url##*/}"
}

downloaded=0
cached=0
failed=0

if [[ -f "$MANIFEST" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue

        name="$(deb_filename_from_url "$line")"
        if [[ "$name" != *.deb ]]; then
            echo "  [!] ERROR: URL does not resolve to a .deb filename, skipping: $line" >&2
            failed=$((failed + 1))
            continue
        fi

        dest="$CACHE_DIR/$name"
        if [[ -s "$dest" ]]; then
            if ! verify_deb "$name" "$dest"; then
                failed=$((failed + 1))
                continue
            fi
            echo "  [=] Cached: $name"
            cached=$((cached + 1))
            continue
        fi

        echo "  [>] Downloading: $line"
        tmp="$dest.download"
        if curl -fL --retry 2 --connect-timeout 20 \
                --speed-limit 1024 --speed-time 30 -o "$tmp" "$line"; then
            mv -f "$tmp" "$dest"
            if ! verify_deb "$name" "$dest"; then
                rm -f "$dest"
                failed=$((failed + 1))
                continue
            fi
            echo "  [+] Downloaded: $name"
            downloaded=$((downloaded + 1))
        else
            rc=$?
            rm -f "$tmp"
            echo "  [!] ERROR: download failed (curl exit $rc), skipping: $line" >&2
            failed=$((failed + 1))
        fi
    done < "$MANIFEST"
else
    echo "  [=] No manifest at $MANIFEST (skipping downloads)"
fi

# Opt-in (vm create --frida): fetch the latest Frida iOS release deb. It's
# re.frida.server (no deps, rootless layout), so the first-boot dpkg -i handles it.
if [[ "${VPHONE_FRIDA:-0}" == "1" && "$ALLOW_INSECURE_PACKAGES" == "1" ]]; then
    echo "  [>] Resolving latest Frida iOS release..."
    frida_url="$(curl -fsSL --connect-timeout 20 \
        https://api.github.com/repos/frida/frida/releases/latest 2>/dev/null \
        | grep -o 'https://[^"]*/frida_[^"]*_iphoneos-arm64\.deb' | head -1)"
    if [[ -n "$frida_url" ]]; then
        frida_name="$(deb_filename_from_url "$frida_url")"
        # Keep only one Frida deb in the cache so a newer "latest" fully replaces
        # any previously-pinned version at install time.
        for old in "$CACHE_DIR"/frida_*_iphoneos-arm64.deb(N); do
            [[ "${old:t}" == "$frida_name" ]] || rm -f "$old"
        done
        dest="$CACHE_DIR/$frida_name"
        if [[ -s "$dest" ]]; then
            echo "  [=] Cached: $frida_name"
            cached=$((cached + 1))
        else
            echo "  [>] Downloading: $frida_url"
            tmp="$dest.download"
            if curl -fL --retry 2 --connect-timeout 20 -o "$tmp" "$frida_url"; then
                mv -f "$tmp" "$dest"
                echo "  [+] Downloaded: $frida_name"
                downloaded=$((downloaded + 1))
            else
                rc=$?
                rm -f "$tmp"
                echo "  [!] ERROR: Frida download failed (curl exit $rc), skipping" >&2
                failed=$((failed + 1))
            fi
        fi
    else
        echo "  [!] ERROR: could not resolve latest Frida iOS deb URL, skipping" >&2
        failed=$((failed + 1))
    fi
fi

total=0
for f in "$CACHE_DIR"/*.deb(N); do
    total=$((total + 1))
done

echo "  [i] debs: $total in cache ($downloaded downloaded, $cached already cached, $failed failed)"

# Return the cache to the invoking user when run under sudo.
if [[ "$(id -u)" == "0" && -n "${SUDO_USER:-}" ]]; then
    chown -R "$SUDO_USER" "$CACHE_DIR" 2>/dev/null || true
fi

exit 0
