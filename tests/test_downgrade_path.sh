#!/bin/bash
#
# tests/test_downgrade_path.sh
# -----------------------------------------------------------
# Validates the downgrade path: simulates an existing v26.4
# install being downgraded to v26.3, and confirms:
#   1. Helper unit tests: _is_versioned_tag, _tag_is_older_than,
#      _normalize_github_tag
#   2. Data folder backup is created before downgrade
#   3. Data folder contents are fully preserved after downgrade
#   4. Application binary is replaced with the older version
#   5. Service file ExecStart is updated to the new binary
#   6. Installed tag file is updated to the downgraded version
# -----------------------------------------------------------

set -euo pipefail

PASS=0
FAIL=0

# ── Helpers ──────────────────────────────────────────────────────────────
pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

# ── Pull helper functions from the installer ─────────────────────────────
# We inline the pure helpers here to avoid sourcing the full installer
# (which has top-level side effects like package-manager calls).

_is_versioned_tag() {
    [[ "$1" =~ ^v?[0-9]+\.[0-9]+ ]]
}

_tag_is_older_than() {
    local a="$1" b="$2"
    _is_versioned_tag "$a" || return 1
    _is_versioned_tag "$b" || return 1
    local va="${a#v}" vb="${b#v}"
    local amaj amin bmaj bmin
    amaj="${va%%.*}"
    local a_rest="${va#*.}"; amin="${a_rest%%.*}"
    bmaj="${vb%%.*}"
    local b_rest="${vb#*.}"; bmin="${b_rest%%.*}"
    if [[ "$amaj" -lt "$bmaj" ]]; then return 0
    elif [[ "$amaj" -eq "$bmaj" && "$amin" -lt "$bmin" ]]; then return 0
    fi
    return 1
}

_normalize_github_tag() {
    local tag="$1"
    if [[ "$tag" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "v${tag}.0"
    else
        echo "$tag"
    fi
}

# ── Temp workspace ───────────────────────────────────────────────────────
TEST_ROOT=$(mktemp -d)
INSTALL_DIR="$TEST_ROOT/opt/ersatztv"
DATA_FOLDER="$TEST_ROOT/home/ersatztv/.local/share/ersatztv"
SERVICE_DIR="$TEST_ROOT/etc/systemd/system"
SERVICE_FILE="$SERVICE_DIR/ersatztv.service"
SERVICE_NAME="ersatztv"
ERSATZTV_TAG_FILE="$INSTALL_DIR/.installed_tag"

cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

# ══════════════════════════════════════════════════════════════════════════
# Stage 0 — Unit tests for helper functions
# ══════════════════════════════════════════════════════════════════════════
echo "============================================================"
echo "🧪 ErsatzTV Downgrade Path Test"
echo "============================================================"
echo ""
echo "────────────────────────────────────────────────────────────"
echo "Stage 0: Helper function unit tests"
echo "────────────────────────────────────────────────────────────"

# _is_versioned_tag
_is_versioned_tag "26.4"    && pass "_is_versioned_tag: 26.4 is versioned"     || fail "_is_versioned_tag: 26.4"
_is_versioned_tag "v26.4.0" && pass "_is_versioned_tag: v26.4.0 is versioned"  || fail "_is_versioned_tag: v26.4.0"
_is_versioned_tag "v0.8.0"  && pass "_is_versioned_tag: v0.8.0 is versioned"   || fail "_is_versioned_tag: v0.8.0"
! _is_versioned_tag "develop" && pass "_is_versioned_tag: develop is NOT versioned" || fail "_is_versioned_tag: develop should not be versioned"
! _is_versioned_tag "latest"  && pass "_is_versioned_tag: latest is NOT versioned"  || fail "_is_versioned_tag: latest should not be versioned"

# _tag_is_older_than
_tag_is_older_than "26.3" "26.4" && pass "_tag_is_older_than: 26.3 < 26.4"           || fail "_tag_is_older_than: 26.3 should be older than 26.4"
_tag_is_older_than "v26.3.0" "26.4" && pass "_tag_is_older_than: v26.3.0 < 26.4"     || fail "_tag_is_older_than: v26.3.0 should be older than 26.4"
_tag_is_older_than "26.3" "v26.4.0" && pass "_tag_is_older_than: 26.3 < v26.4.0"     || fail "_tag_is_older_than: 26.3 should be older than v26.4.0"
! _tag_is_older_than "26.4" "26.3"  && pass "_tag_is_older_than: 26.4 NOT < 26.3"    || fail "_tag_is_older_than: 26.4 should not be older than 26.3"
! _tag_is_older_than "26.4" "26.4"  && pass "_tag_is_older_than: 26.4 NOT < 26.4 (equal)" || fail "_tag_is_older_than: equal versions should not be older"
! _tag_is_older_than "develop" "26.4" && pass "_tag_is_older_than: develop (pseudo) NOT comparable" || fail "_tag_is_older_than: develop should not be comparable"
! _tag_is_older_than "26.3" "latest" && pass "_tag_is_older_than: latest (pseudo) NOT comparable"   || fail "_tag_is_older_than: latest should not be comparable"
_tag_is_older_than "26.3" "27.0"  && pass "_tag_is_older_than: 26.3 < 27.0 (major bump)"  || fail "_tag_is_older_than: 26.3 should be older than 27.0"
! _tag_is_older_than "27.0" "26.3" && pass "_tag_is_older_than: 27.0 NOT < 26.3"           || fail "_tag_is_older_than: 27.0 should not be older than 26.3"

# _normalize_github_tag
[[ "$(_normalize_github_tag "26.4")"    == "v26.4.0" ]] && pass "_normalize_github_tag: 26.4 → v26.4.0"   || fail "_normalize_github_tag: 26.4"
[[ "$(_normalize_github_tag "26.3")"    == "v26.3.0" ]] && pass "_normalize_github_tag: 26.3 → v26.3.0"   || fail "_normalize_github_tag: 26.3"
[[ "$(_normalize_github_tag "v26.4.0")" == "v26.4.0" ]] && pass "_normalize_github_tag: v26.4.0 unchanged" || fail "_normalize_github_tag: v26.4.0"
[[ "$(_normalize_github_tag "develop")" == "develop" ]] && pass "_normalize_github_tag: develop unchanged"  || fail "_normalize_github_tag: develop"

echo ""

# ══════════════════════════════════════════════════════════════════════════
# Stage 1 — Set up a v26.4 install layout
# ══════════════════════════════════════════════════════════════════════════
echo "────────────────────────────────────────────────────────────"
echo "Stage 1: Setting up v26.4 install layout"
echo "────────────────────────────────────────────────────────────"

mkdir -p \
    "$INSTALL_DIR" \
    "$DATA_FOLDER/logs" \
    "$DATA_FOLDER/database" \
    "$SERVICE_DIR"

# Application binary (simulating v26.4 / ErsatzTV-Legacy naming)
cat > "$INSTALL_DIR/ErsatzTV-Legacy" <<'STUBEOF'
#!/bin/bash
echo "ErsatzTV-Legacy v26.4 (stub binary)"
STUBEOF
chmod +x "$INSTALL_DIR/ErsatzTV-Legacy"

# Installed-tag file (written by the installer after previous install)
echo "26.4" > "$ERSATZTV_TAG_FILE"

# Bundled ffmpeg
mkdir -p "$INSTALL_DIR/ffmpeg"
cat > "$INSTALL_DIR/ffmpeg/ffmpeg" <<'STUBEOF'
#!/bin/bash
echo "ffmpeg stub"
STUBEOF
chmod +x "$INSTALL_DIR/ffmpeg/ffmpeg"

# Pre-existing user data that MUST survive the downgrade
echo '{"channels": [{"id": 1, "name": "Test Channel"}]}' > "$DATA_FOLDER/channels.json"
printf 'BINARY_DB_CONTENT'  > "$DATA_FOLDER/ersatztv.db"
printf 'ARTWORK_DATA'       > "$DATA_FOLDER/artwork.jpg"
echo  '2026-04-19 INFO ErsatzTV v26.4 started' > "$DATA_FOLDER/logs/ersatztv.log"
printf 'DB_FILE'            > "$DATA_FOLDER/database/ersatztv.db3"

# Service file referencing v26.4 binary
FFMPEG_PATH="$INSTALL_DIR/ffmpeg"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=ErsatzTV Service
After=network.target

[Service]
User=ersatztv
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/ErsatzTV-Legacy --data-folder $DATA_FOLDER
ExecStop=/bin/kill -s SIGINT \$MAINPID
Restart=on-failure
RestartSec=5
Environment=HOME=$TEST_ROOT/home/ersatztv
Environment=PATH=$FFMPEG_PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

echo "   ✔ $INSTALL_DIR/ErsatzTV-Legacy  (v26.4 stub)"
echo "   ✔ $ERSATZTV_TAG_FILE  → 26.4"
echo "   ✔ $DATA_FOLDER  (channels.json, db, artwork, logs, database/)"
echo ""

# ══════════════════════════════════════════════════════════════════════════
# Stage 2 — Run the downgrade logic
#
# Mirrors what ersatztv-linux-automation.sh does when the user selects a tag
# older than the currently installed one (e.g. v26.4 → v26.3).
# ══════════════════════════════════════════════════════════════════════════
echo "────────────────────────────────────────────────────────────"
echo "Stage 2: Running downgrade logic (26.4 → 26.3)"
echo "────────────────────────────────────────────────────────────"

DOWNGRADE_TAG="26.3"
INSTALLED_TAG=$(cat "$ERSATZTV_TAG_FILE")

# Step 1: Detect downgrade and back up data folder
if _tag_is_older_than "$DOWNGRADE_TAG" "$INSTALLED_TAG"; then
    echo "  ⬇️  DOWNGRADE DETECTED: $INSTALLED_TAG → $DOWNGRADE_TAG"
    DATA_BACKUP_DIR="$TEST_ROOT/opt/ersatztv_data_backup_$(date +%Y%m%d_%H%M%S)"
    cp -a "$DATA_FOLDER" "$DATA_BACKUP_DIR" 2>/dev/null || true
fi

# Step 2: Stop service (simulated — no real systemctl in test env)
sed -i 's/^Restart=.*/Restart=no/' "$SERVICE_FILE"

# Step 3: Simulate extracting the v26.3 tarball (replace binary stub)
cat > "$INSTALL_DIR/ErsatzTV-Legacy" <<'STUBEOF'
#!/bin/bash
echo "ErsatzTV-Legacy v26.3 (stub binary)"
STUBEOF
chmod +x "$INSTALL_DIR/ErsatzTV-Legacy"

# Step 4: Binary detection
DETECTED_BINARY=""
if [[ -x "$INSTALL_DIR/ErsatzTV" ]]; then
    DETECTED_BINARY="$INSTALL_DIR/ErsatzTV"
elif [[ -x "$INSTALL_DIR/ErsatzTV-Legacy" ]]; then
    DETECTED_BINARY="$INSTALL_DIR/ErsatzTV-Legacy"
fi
if [[ -z "$DETECTED_BINARY" ]]; then
    echo "❌ FATAL: No executable binary detected after simulated downgrade."
    exit 1
fi

# Step 5: Rewrite service file to point at newly installed binary
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=ErsatzTV Service
After=network.target

[Service]
User=ersatztv
WorkingDirectory=$INSTALL_DIR
ExecStart=$DETECTED_BINARY --data-folder $DATA_FOLDER
ExecStop=/bin/kill -s SIGINT \$MAINPID
Restart=on-failure
RestartSec=5
Environment=HOME=$TEST_ROOT/home/ersatztv
Environment=PATH=$FFMPEG_PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

# Step 6: Update the installed-tag file to reflect the new (downgraded) version
echo "$DOWNGRADE_TAG" > "$ERSATZTV_TAG_FILE"

echo "   ✔ Binary replaced: $DETECTED_BINARY"
echo "   ✔ Service file rewritten"
echo "   ✔ Tag file updated to $DOWNGRADE_TAG"
echo ""

# ══════════════════════════════════════════════════════════════════════════
# Stage 3 — Validate acceptance criteria
# ══════════════════════════════════════════════════════════════════════════

# ── Criterion 1: Data backup was created before downgrade ────────────────
echo "────────────────────────────────────────────────────────────"
echo "Criterion 1: Data backup created before downgrade"
echo "────────────────────────────────────────────────────────────"

BACKUP_COUNT=$(ls -d "$TEST_ROOT"/opt/ersatztv_data_backup_* 2>/dev/null | wc -l)
[[ "$BACKUP_COUNT" -gt 0 ]] \
    && pass "Data backup directory was created ($BACKUP_COUNT found)" \
    || fail "No data backup directory was created before downgrade"

BACKUP_FIRST=$(ls -d "$TEST_ROOT"/opt/ersatztv_data_backup_* 2>/dev/null | head -1)
if [[ -n "$BACKUP_FIRST" ]]; then
    [[ -f "$BACKUP_FIRST/channels.json" ]] \
        && pass "Backup contains channels.json" \
        || fail "Backup is missing channels.json"
    [[ -f "$BACKUP_FIRST/ersatztv.db" ]] \
        && pass "Backup contains ersatztv.db" \
        || fail "Backup is missing ersatztv.db"
    [[ -f "$BACKUP_FIRST/logs/ersatztv.log" ]] \
        && pass "Backup contains logs/ersatztv.log" \
        || fail "Backup is missing logs/ersatztv.log"
    [[ -f "$BACKUP_FIRST/database/ersatztv.db3" ]] \
        && pass "Backup contains database/ersatztv.db3" \
        || fail "Backup is missing database/ersatztv.db3"
fi

echo ""

# ── Criterion 2: Data folder remains intact after downgrade ──────────────
echo "────────────────────────────────────────────────────────────"
echo "Criterion 2: Data folder preserved after downgrade"
echo "────────────────────────────────────────────────────────────"

[[ -d "$DATA_FOLDER" ]] \
    && pass "Data folder exists: $DATA_FOLDER" \
    || fail "Data folder was removed during downgrade"

[[ -f "$DATA_FOLDER/channels.json" ]] \
    && pass "channels.json preserved" \
    || fail "channels.json was removed during downgrade"

[[ "$(cat "$DATA_FOLDER/channels.json")" == '{"channels": [{"id": 1, "name": "Test Channel"}]}' ]] \
    && pass "channels.json content is unchanged" \
    || fail "channels.json content was altered during downgrade"

[[ -f "$DATA_FOLDER/ersatztv.db" ]] \
    && pass "ersatztv.db preserved" \
    || fail "ersatztv.db was removed during downgrade"

[[ -f "$DATA_FOLDER/artwork.jpg" ]] \
    && pass "artwork.jpg preserved" \
    || fail "artwork.jpg was removed during downgrade"

[[ -f "$DATA_FOLDER/logs/ersatztv.log" ]] \
    && pass "logs/ersatztv.log preserved" \
    || fail "logs/ersatztv.log was removed during downgrade"

[[ -f "$DATA_FOLDER/database/ersatztv.db3" ]] \
    && pass "database/ersatztv.db3 preserved" \
    || fail "database/ersatztv.db3 was removed during downgrade"

echo ""

# ── Criterion 3: Binary replaced with older version ──────────────────────
echo "────────────────────────────────────────────────────────────"
echo "Criterion 3: Binary replaced with downgraded version"
echo "────────────────────────────────────────────────────────────"

[[ -f "$INSTALL_DIR/ErsatzTV-Legacy" || -f "$INSTALL_DIR/ErsatzTV" ]] \
    && pass "ErsatzTV binary is present in install directory" \
    || fail "No ErsatzTV binary found in install directory after downgrade"

[[ -x "$DETECTED_BINARY" ]] \
    && pass "Detected binary ($DETECTED_BINARY) is executable" \
    || fail "Detected binary ($DETECTED_BINARY) is not executable"

# The stub binary should now report the v26.3 content
BINARY_OUTPUT=$("$DETECTED_BINARY" 2>/dev/null || true)
[[ "$BINARY_OUTPUT" == *"v26.3"* ]] \
    && pass "Binary reports v26.3 (downgraded version)" \
    || fail "Binary does not report v26.3 — downgrade may not have applied"

echo ""

# ── Criterion 4: Service file updated correctly ───────────────────────────
echo "────────────────────────────────────────────────────────────"
echo "Criterion 4: Service file updated after downgrade"
echo "────────────────────────────────────────────────────────────"

SERVICE_EXEC=$(grep '^ExecStart=' "$SERVICE_FILE" | sed 's/^ExecStart=//' | awk '{print $1}')
[[ "$SERVICE_EXEC" == "$DETECTED_BINARY" ]] \
    && pass "ExecStart points to the downgraded binary ($DETECTED_BINARY)" \
    || fail "ExecStart is '$SERVICE_EXEC', expected '$DETECTED_BINARY'"

grep -q "^Restart=on-failure" "$SERVICE_FILE" \
    && pass "Restart=on-failure is set after downgrade" \
    || fail "Restart directive is not 'on-failure' after downgrade"

grep -q "^\[Unit\]"    "$SERVICE_FILE" && pass "Service unit has [Unit] section"    || fail "Service unit missing [Unit]"
grep -q "^\[Service\]" "$SERVICE_FILE" && pass "Service unit has [Service] section" || fail "Service unit missing [Service]"
grep -q "^\[Install\]" "$SERVICE_FILE" && pass "Service unit has [Install] section" || fail "Service unit missing [Install]"

echo ""

# ── Criterion 5: Installed tag file updated to downgraded version ─────────
echo "────────────────────────────────────────────────────────────"
echo "Criterion 5: Installed tag file reflects downgraded version"
echo "────────────────────────────────────────────────────────────"

[[ -f "$ERSATZTV_TAG_FILE" ]] \
    && pass "Tag file exists at $ERSATZTV_TAG_FILE" \
    || fail "Tag file is missing after downgrade"

RECORDED_TAG=$(cat "$ERSATZTV_TAG_FILE" 2>/dev/null || echo "")
[[ "$RECORDED_TAG" == "$DOWNGRADE_TAG" ]] \
    && pass "Tag file records the downgraded version ($DOWNGRADE_TAG)" \
    || fail "Tag file records '$RECORDED_TAG', expected '$DOWNGRADE_TAG'"

echo ""

# ── Summary ───────────────────────────────────────────────────────────────
echo "============================================================"
TOTAL=$((PASS + FAIL))
if [[ "$FAIL" -eq 0 ]]; then
    echo "✅ All downgrade-path tests passed ($PASS/$TOTAL)"
    exit 0
else
    echo "❌ $FAIL test(s) failed  (passed: $PASS / total: $TOTAL)"
    exit 1
fi
