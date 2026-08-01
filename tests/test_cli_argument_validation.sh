#!/bin/bash
#
# tests/test_cli_argument_validation.sh
# -----------------------------------------------------------
# Validates lifecycle CLI argument behavior:
#   1. Missing action shows usage and exits non-zero.
#   2. Conflicting actions are rejected.
#   3. Unknown arguments are rejected.
#   4. --purge is uninstall-only.
#   5. --version reports automation version.
# -----------------------------------------------------------

set -euo pipefail

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/ersatztv-linux-automation.sh"

echo "============================================================"
echo "🧪 ErsatzTV CLI Argument Validation Test"
echo "============================================================"
echo ""

if bash "$SCRIPT" >/tmp/ersatztv-test.out 2>&1; then
  fail "Running without a primary action should fail"
else
  grep -q "Usage:" /tmp/ersatztv-test.out \
    && pass "Running without a primary action prints usage" \
    || fail "Missing-action output did not include usage"
fi

if bash "$SCRIPT" --install --upgrade >/tmp/ersatztv-test.out 2>&1; then
  fail "Conflicting primary actions should fail"
else
  grep -q "Conflicting actions" /tmp/ersatztv-test.out \
    && pass "Conflicting primary actions are rejected" \
    || fail "Conflicting-action error not found"
fi

if bash "$SCRIPT" --not-a-real-flag >/tmp/ersatztv-test.out 2>&1; then
  fail "Unknown option should fail"
else
  grep -q "Unknown argument" /tmp/ersatztv-test.out \
    && pass "Unknown option is rejected" \
    || fail "Unknown-option error not found"
fi

if bash "$SCRIPT" --upgrade --purge >/tmp/ersatztv-test.out 2>&1; then
  fail "--purge with non-uninstall action should fail"
else
  grep -q -- "--purge can only be used with --uninstall" /tmp/ersatztv-test.out \
    && pass "--purge is restricted to --uninstall" \
    || fail "--purge validation error not found"
fi

if [[ "$(bash "$SCRIPT" --version 2>/dev/null || true)" == "ErsatzTV Linux Automation 1.3.0" ]]; then
  pass "--version reports automation script version"
else
  fail "--version output did not match expected version"
fi

rm -f /tmp/ersatztv-test.out

echo ""
echo "============================================================"
TOTAL=$((PASS + FAIL))
if [[ "$FAIL" -eq 0 ]]; then
  echo "✅ All CLI-argument validation tests passed ($PASS/$TOTAL)"
  exit 0
else
  echo "❌ $FAIL test(s) failed  (passed: $PASS / total: $TOTAL)"
  exit 1
fi
