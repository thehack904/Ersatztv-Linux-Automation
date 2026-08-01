#!/bin/bash
# Regression test: resolver diagnostics must not contaminate the FFmpeg version,
# and RESOLVED_* metadata must survive after the resolver returns.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Load definitions only; do not execute the script's main entry point.
source <(sed '/^# --- Main Execution /,$d' "$ROOT_DIR/ersatztv-linux-automation.sh")

PASS=0
FAIL=0
pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

_fetch_selected_release_json() {
    printf '%s\n' '{"tag_name":"v26.7.1","html_url":"https://example.invalid/v26.7.1","body":"Maintenance release","assets":[]}'
}

curl() {
    case "$*" in
        *'/releases?per_page=100'*)
            printf '%s\n' '[{"tag_name":"v26.7.1","body":"Maintenance release","assets":[]},{"tag_name":"v26.7.0","body":"Bundled FFmpeg was upgraded from 7.1.1 to 8.1.2","assets":[]}]'
            ;;
        *) return 1 ;;
    esac
}

output_file=$(mktemp)
trap 'rm -f "$output_file"' EXIT

if _resolve_required_ffmpeg_tag develop >"$output_file"; then
    pass "Resolver succeeds for inherited FFmpeg requirement"
else
    fail "Resolver should succeed"
fi

[[ "$RESOLVED_ERSATZTV_TAG" == "v26.7.1" ]] \
    && pass "Resolved ErsatzTV tag survives resolver call" \
    || fail "Resolved ErsatzTV tag was lost"
[[ "$RESOLVED_FFMPEG_VERSION" == "8.1.2" ]] \
    && pass "Resolved FFmpeg version remains a clean scalar" \
    || fail "Expected 8.1.2, got '$RESOLVED_FFMPEG_VERSION'"
[[ "$RESOLVED_FFMPEG_SOURCE" == "inherited" ]] \
    && pass "Requirement source survives resolver call" \
    || fail "Expected inherited source, got '$RESOLVED_FFMPEG_SOURCE'"
[[ "$RESOLVED_FFMPEG_CONFIDENCE" == "inherited" ]] \
    && pass "Requirement confidence survives resolver call" \
    || fail "Expected inherited confidence, got '$RESOLVED_FFMPEG_CONFIDENCE'"

grep -q 'Inspecting ErsatzTV release: v26.7.1' "$output_file" \
    && pass "Diagnostic output remains visible separately" \
    || fail "Expected resolver diagnostic output"

if [[ "$RESOLVED_FFMPEG_VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    pass "Resolved version is safe for numeric comparison and URL construction"
else
    fail "Resolved version contains non-version text"
fi

echo
TOTAL=$((PASS + FAIL))
if [[ "$FAIL" -eq 0 ]]; then
    echo "✅ All resolver-state tests passed ($PASS/$TOTAL)"
else
    echo "❌ $FAIL resolver-state test(s) failed (passed: $PASS / total: $TOTAL)"
    exit 1
fi
