#!/bin/bash
#
# tests/test_lock_handling.sh
# -----------------------------------------------------------
# Validates lifecycle lock behavior:
#   1. Duplicate invocation is rejected while another process holds the lock.
#   2. A stale PID marker does not prevent a new lock acquisition.
# -----------------------------------------------------------

set -euo pipefail

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

LOCK_ROOT=$(mktemp -d)
LOCK_FILE="$LOCK_ROOT/ersatztv-linux-automation.lock"
LOCK_PID_FILE="$LOCK_ROOT/ersatztv-linux-automation.pid"
LOCK_FD=9
LOCK_METHOD=""

cleanup() {
    if [[ -n "${HOLDER_PID:-}" ]]; then
        kill "$HOLDER_PID" 2>/dev/null || true
        wait "$HOLDER_PID" 2>/dev/null || true
    fi
    rm -rf "$LOCK_ROOT"
}
trap cleanup EXIT

log_error() { echo "❌ $*" >&2; }

acquire_lock() {
    mkdir -p "$(dirname "$LOCK_FILE")"
    if command -v flock >/dev/null 2>&1; then
        eval "exec ${LOCK_FD}>\"$LOCK_FILE\""
        if ! flock -n "$LOCK_FD"; then
            local active_pid=""
            active_pid=$(cat "$LOCK_PID_FILE" 2>/dev/null || true)
            log_error "Another ErsatzTV automation operation is running${active_pid:+ (pid $active_pid)}."
            exit 1
        fi
        echo "$$" > "$LOCK_PID_FILE"
        LOCK_METHOD="flock"
        return 0
    fi

    if [[ -f "$LOCK_PID_FILE" ]]; then
        local existing_pid
        existing_pid=$(cat "$LOCK_PID_FILE" 2>/dev/null || true)
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            log_error "Another ErsatzTV automation operation is running (pid $existing_pid)."
            exit 1
        fi
        rm -f "$LOCK_PID_FILE"
    fi
    echo "$$" > "$LOCK_PID_FILE"
    LOCK_METHOD="pidfile"
}

release_lock() {
    if [[ -f "$LOCK_PID_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_PID_FILE" 2>/dev/null || true)
        if [[ "$lock_pid" == "$$" ]]; then
            rm -f "$LOCK_PID_FILE"
        fi
    fi
    if [[ "$LOCK_METHOD" == "flock" ]]; then
        flock -u "$LOCK_FD" 2>/dev/null || true
        rm -f "$LOCK_FILE"
    fi
}

echo "============================================================"
echo "🧪 ErsatzTV Lock Handling Test"
echo "============================================================"
echo ""

echo "────────────────────────────────────────────────────────────"
echo "Stage 1: Duplicate invocation while lock is held"
echo "────────────────────────────────────────────────────────────"

(
    LOCK_FILE="$LOCK_FILE"
    LOCK_PID_FILE="$LOCK_PID_FILE"
    LOCK_FD=9
    LOCK_METHOD=""
    acquire_lock
    echo "$$" > "$LOCK_ROOT/holder.pid"
    sleep 5
    release_lock
) &
HOLDER_PID=$!

for _ in $(seq 1 50); do
    [[ -f "$LOCK_ROOT/holder.pid" ]] && break
    sleep 0.1
done

if [[ ! -f "$LOCK_ROOT/holder.pid" ]]; then
    fail "Lock holder process did not initialize"
else
    if (acquire_lock) >/dev/null 2>&1; then
        fail "Second invocation unexpectedly acquired lock"
        release_lock
    else
        pass "Second invocation is blocked while first holder is active"
    fi
fi

wait "$HOLDER_PID" 2>/dev/null || true
unset HOLDER_PID
LOCK_METHOD=""

echo ""
echo "────────────────────────────────────────────────────────────"
echo "Stage 2: Stale lock marker recovery"
echo "────────────────────────────────────────────────────────────"

echo "999999" > "$LOCK_PID_FILE"
if acquire_lock >/dev/null 2>&1; then
    current_pid=$(cat "$LOCK_PID_FILE" 2>/dev/null || true)
    [[ "$current_pid" == "$$" ]] \
        && pass "Stale PID marker is replaced by current process PID" \
        || fail "PID marker was not refreshed after successful lock acquisition"
else
    fail "Lock acquisition failed with only a stale PID marker present"
fi

release_lock
[[ ! -f "$LOCK_PID_FILE" ]] \
    && pass "Lock PID marker removed on release" \
    || fail "Lock PID marker was not removed on release"

echo ""
echo "============================================================"
TOTAL=$((PASS + FAIL))
if [[ "$FAIL" -eq 0 ]]; then
    echo "✅ All lock-handling tests passed ($PASS/$TOTAL)"
    exit 0
else
    echo "❌ $FAIL test(s) failed  (passed: $PASS / total: $TOTAL)"
    exit 1
fi
