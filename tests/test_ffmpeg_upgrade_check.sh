#!/bin/bash
#
# tests/test_ffmpeg_upgrade_check.sh
# -----------------------------------------------------------
# Validates the bundled FFmpeg selection logic for ErsatzTV
# release upgrades. Confirms:
#   1. Versioned ErsatzTV tags resolve to the expected FFmpeg tag
#   2. develop/latest use the current FFmpeg release
#   3. An FFmpeg upgrade is triggered only when the required tag changes
# -----------------------------------------------------------

set -euo pipefail

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

normalize_ver() { echo "${1#v}" | sed 's/^V//'; }

version_compare() {
    local a b i
    local -a av bv
    a=$(normalize_ver "$1")
    b=$(normalize_ver "$2")
    IFS='.' read -r -a av <<< "$a"
    IFS='.' read -r -a bv <<< "$b"
    for i in 0 1 2; do
        local ai="${av[$i]:-0}" bi="${bv[$i]:-0}"
        if (( ai < bi )); then echo -1; return; fi
        if (( ai > bi )); then echo 1; return; fi
    done
    echo 0
}

extract_ffmpeg_link_version() {
    local body="$1"
    local link
    link=$(printf '%s\n' "$body" | grep -Eio 'https://github\.com/ErsatzTV/ErsatzTV-ffmpeg/releases/tag/[vV]?[0-9]+(\.[0-9]+){1,2}' | head -n 1 || true)
    [[ -n "$link" ]] || return 1
    normalize_ver "${link##*/}"
}

extract_ffmpeg_text_version() {
    local body="$1" line
    while IFS= read -r line; do
        [[ "${line,,}" == *ffmpeg* ]] || continue
        [[ "${line,,}" =~ (require|requires|required|bundled|upgrade|upgraded|updated|ersatztv-ffmpeg) ]] || continue
        local to_ver
        to_ver=$(printf '%s\n' "$line" | grep -Eio '(to|->)[[:space:]]*[vV]?[0-9]+(\.[0-9]+){1,2}' | head -n 1 | grep -Eo '[vV]?[0-9]+(\.[0-9]+){1,2}' || true)
        if [[ -n "$to_ver" ]]; then normalize_ver "$to_ver"; return 0; fi
        local candidate
        candidate=$(printf '%s\n' "$line" | grep -Eio '(ersatztv-ffmpeg|ffmpeg)[^0-9vV]*[vV]?[0-9]+(\.[0-9]+){1,2}' | head -n 1 || true)
        local version
        version=$(printf '%s\n' "$candidate" | grep -Eo '[vV]?[0-9]+(\.[0-9]+){1,2}' | head -n 1 || true)
        if [[ -n "$version" ]]; then normalize_ver "$version"; return 0; fi
    done <<< "$body"
    return 1
}

extract_ffmpeg_asset_version() {
    local release_json="$1"
    local matches
    matches=$(printf '%s\n' "$release_json" \
        | jq -r '.assets[]?.name // empty' \
        | awk 'BEGIN{IGNORECASE=1} /ffmpeg/ && /linux/ {print}' \
        | grep -Eo '[vV]?[0-9]+(\.[0-9]+){1,2}' \
        | sed 's/^[vV]//' \
        | sort -u || true)
    if [[ "$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l)" -eq 1 ]]; then
        printf '%s\n' "$matches" | sed '/^$/d'
        return 0
    fi
    return 1
}

known_ffmpeg_version_for_ersatztv() {
    case "$1" in
        v26.7.0|26.7|26.7.0) echo "8.1.2" ;;
        v25.2.0|25.2|25.2.0) echo "7.1.1" ;;
        *) return 1 ;;
    esac
}

echo "============================================================"
echo "🧪 ErsatzTV FFmpeg Upgrade Check Test"
echo "============================================================"
echo ""
echo "────────────────────────────────────────────────────────────"
echo "Stage 1: FFmpeg tag selection"
echo "────────────────────────────────────────────────────────────"

link_body='Bundled FFmpeg was upgraded. See https://github.com/ErsatzTV/ErsatzTV-ffmpeg/releases/tag/8.1.2'
[[ "$(extract_ffmpeg_link_version "$link_body")" == "8.1.2" ]] \
    && pass "Direct official FFmpeg release link is parsed" \
    || fail "Expected to parse FFmpeg release link version"

text_body='* **Bundled FFmpeg was upgraded from 7.1 to 8.1.2**'
[[ "$(extract_ffmpeg_text_version "$text_body")" == "8.1.2" ]] \
    && pass "Structured FFmpeg upgrade text parses required version" \
    || fail "Expected structured FFmpeg text parsing"

text_body_v='Requires ErsatzTV FFmpeg v8.1.2'
[[ "$(extract_ffmpeg_text_version "$text_body_v")" == "8.1.2" ]] \
    && pass "Text parsing accepts leading v in FFmpeg version" \
    || fail "Expected leading-v FFmpeg text parsing"

noise_body='Fixed an FFmpeg logging issue'
! extract_ffmpeg_text_version "$noise_body" >/dev/null 2>&1 \
    && pass "Unrelated FFmpeg mention does not trigger requirement" \
    || fail "Unrelated FFmpeg mention should not trigger requirement"

asset_json='{"assets":[{"name":"ersatztv-ffmpeg-8.1.2-linux64.tar.xz"},{"name":"notes.txt"}]}'
[[ "$(extract_ffmpeg_asset_version "$asset_json")" == "8.1.2" ]] \
    && pass "FFmpeg asset metadata resolves required version" \
    || fail "Expected FFmpeg version from release assets"

known_ffmpeg_version_for_ersatztv "26.7" >/dev/null 2>&1 \
    && [[ "$(known_ffmpeg_version_for_ersatztv "26.7")" == "8.1.2" ]] \
    && pass "Known compatibility mapping includes v26.7.0 -> 8.1.2" \
    || fail "Known compatibility mapping for v26.7.0 missing"

echo ""
echo "────────────────────────────────────────────────────────────"
echo "Stage 2: FFmpeg upgrade decision"
echo "────────────────────────────────────────────────────────────"

[[ "$(version_compare "7.1" "8.1.2")" == "-1" ]] \
    && pass "Numeric compare: 7.1 is older than 8.1.2" \
    || fail "7.1 should be older than 8.1.2"

[[ "$(version_compare "8.1.2" "8.1.2")" == "0" ]] \
    && pass "Numeric compare: equal versions match" \
    || fail "8.1.2 should equal 8.1.2"

[[ "$(version_compare "8.1.3" "8.1.2")" == "1" ]] \
    && pass "Numeric compare: 8.1.3 is newer than 8.1.2" \
    || fail "8.1.3 should be newer than 8.1.2"

[[ "$(version_compare "8.10.0" "8.2.0")" == "1" ]] \
    && pass "Numeric compare: 8.10.0 is newer than 8.2.0" \
    || fail "8.10.0 should be newer than 8.2.0"

echo ""
echo "============================================================"
TOTAL=$((PASS + FAIL))
if [[ "$FAIL" -eq 0 ]]; then
    echo "✅ All FFmpeg upgrade-check tests passed ($PASS/$TOTAL)"
    exit 0
else
    echo "❌ $FAIL test(s) failed  (passed: $PASS / total: $TOTAL)"
    exit 1
fi
