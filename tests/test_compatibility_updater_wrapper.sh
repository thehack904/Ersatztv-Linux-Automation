#!/bin/bash
#
# tests/test_compatibility_updater_wrapper.sh
# -----------------------------------------------------------
# Validates the compatibility updater wrapper shape:
#   1. Wrapper delegates to canonical management command.
#   2. Wrapper uses the upgrade action and forwards arguments.
#   3. Wrapper is a thin delegator (no embedded update engine).
# -----------------------------------------------------------

set -euo pipefail

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

TEST_ROOT=$(mktemp -d)
UPDATER_PATH="$TEST_ROOT/update_linux_ersatztv.sh"

cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

install_updater() {
    cat <<'EOS' > "$UPDATER_PATH"
#!/bin/bash
set -euo pipefail
echo "Warning: command \"update_linux_ersatztv.sh\" is deprecated." >&2
echo "Use \"ersatztv-linux-automation --upgrade\" instead." >&2
exec /usr/local/sbin/ersatztv-linux-automation --upgrade "$@"
EOS
    chmod +x "$UPDATER_PATH"
}

echo "============================================================"
echo "🧪 ErsatzTV Compatibility Updater Wrapper Test"
echo "============================================================"
echo ""

install_updater

[[ -x "$UPDATER_PATH" ]] \
    && pass "Compatibility updater wrapper is created and executable" \
    || fail "Compatibility updater wrapper was not created as executable"

grep -q '^exec /usr/local/sbin/ersatztv-linux-automation --upgrade "\$@"$' "$UPDATER_PATH" \
    && pass "Wrapper delegates to canonical automation command with --upgrade" \
    || fail "Wrapper does not delegate to canonical automation command"

TOTAL_LINES=$(wc -l < "$UPDATER_PATH")
NON_COMMENT_NON_BLANK_LINES=$(grep -Ec '^[^[:space:]#]' "$UPDATER_PATH")
[[ "$TOTAL_LINES" -eq 5 && "$NON_COMMENT_NON_BLANK_LINES" -eq 4 ]] \
    && pass "Wrapper remains thin and contains only shebang/set/warn/exec lines" \
    || fail "Wrapper includes unexpected extra logic"

echo ""
echo "============================================================"
TOTAL=$((PASS + FAIL))
if [[ "$FAIL" -eq 0 ]]; then
    echo "✅ All compatibility-wrapper tests passed ($PASS/$TOTAL)"
    exit 0
else
    echo "❌ $FAIL test(s) failed  (passed: $PASS / total: $TOTAL)"
    exit 1
fi
