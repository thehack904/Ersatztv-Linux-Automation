#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source <(sed '/^# --- Main Execution /,$d' "$ROOT_DIR/ersatztv-linux-automation.sh")

PASS=0
FAIL=0
pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

mock_release() {
    cat <<'JSON'
{"tag_name":"8.1.2","assets":[
 {"id":10,"created_at":"2026-07-22T18:00:00Z","name":"ffmpeg-8.1.2-linux-x64.tar.xz","browser_download_url":"https://example.invalid/ffmpeg-8.1.2-linux-x64.tar.xz"},
 {"name":"ffmpeg-8.1.2-linux-arm64.tar.xz","browser_download_url":"https://example.invalid/ffmpeg-8.1.2-linux-arm64.tar.xz"},
 {"name":"ffmpeg-8.1.2-windows-x64.zip","browser_download_url":"https://example.invalid/windows.zip"}
]}
JSON
}

curl() { mock_release; }

ARCH=x86_64
url=$(resolve_ffmpeg_asset 8.1.2)
[[ "$url" == "https://example.invalid/ffmpeg-8.1.2-linux-x64.tar.xz" ]] \
    && pass "x86_64 resolves linux-x64 asset" || fail "x86_64 asset mismatch: $url"

ARCH=aarch64
url=$(resolve_ffmpeg_asset 8.1.2)
[[ "$url" == "https://example.invalid/ffmpeg-8.1.2-linux-arm64.tar.xz" ]] \
    && pass "aarch64 resolves linux-arm64 asset" || fail "arm64 asset mismatch: $url"

# Releases may retain an older build alongside a newer replacement build.
curl() { cat <<'JSON'
{"tag_name":"8.1.2","assets":[
 {"id":100,"created_at":"2026-07-22T18:00:00Z","name":"ffmpeg-n8.1.2-etv-g668ee329-linux64-gpl-8.1.tar.xz","browser_download_url":"https://example.invalid/old.tar.xz"},
 {"id":200,"created_at":"2026-07-27T18:00:00Z","name":"ffmpeg-n8.1.2-etv-g82f576a8-linux64-gpl-8.1.tar.xz","browser_download_url":"https://example.invalid/new.tar.xz"}
]}
JSON
}
ARCH=x86_64
err_multi=$(mktemp)
url=$(resolve_ffmpeg_asset 8.1.2 2>"$err_multi")
if [[ "$url" == "https://example.invalid/new.tar.xz" ]] && grep -q 'selecting newest: ffmpeg-n8.1.2-etv-g82f576a8-linux64' "$err_multi"; then
    pass "duplicate architecture assets select newest uploaded build"
else
    fail "duplicate asset selection mismatch: $url"
fi
rm -f "$err_multi"

curl() { return 22; }
if resolve_ffmpeg_asset 8.1.2 >/dev/null 2>&1; then
    fail "API failure should return nonzero"
else
    pass "API failure returns nonzero instead of an empty success"
fi

curl() { printf '%s\n' '{"tag_name":"8.1.2","assets":[{"name":"windows.zip","browser_download_url":"https://example.invalid/windows.zip"}]}'; }
ARCH=x86_64
err=$(mktemp)
trap 'rm -f "$err"' EXIT
if resolve_ffmpeg_asset 8.1.2 >/dev/null 2>"$err"; then
    fail "Missing Linux asset should fail"
elif grep -q 'Available release assets' "$err" && grep -q 'windows.zip' "$err"; then
    pass "Missing match prints available asset names"
else
    fail "Missing match did not print useful diagnostics"
fi

TOTAL=$((PASS + FAIL))
if [[ "$FAIL" -eq 0 ]]; then
    echo "✅ All FFmpeg asset-resolution tests passed ($PASS/$TOTAL)"
else
    echo "❌ $FAIL FFmpeg asset-resolution test(s) failed"
    exit 1
fi
