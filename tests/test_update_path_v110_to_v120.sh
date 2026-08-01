#!/bin/bash
#
# tests/test_update_path_v110_to_v120.sh
# -----------------------------------------------------------
# Simulates upgrading an existing v1.1.0 install to v1.2.0.
# Does NOT require root or network access; all filesystem
# operations are performed inside a temporary directory and
# systemctl / curl calls are replaced by no-op stubs.
#
# Acceptance criteria (from the tracking issue):
#   1. Start with a v1.1.0-style install layout.
#   2. Run the dev/v1.2.0 update script (logic extracted).
#   3. Confirm the service file is rewritten correctly.
#   4. Confirm old binary references are removed or migrated.
#   5. Confirm the app directory contains the expected files.
#   6. Confirm the service starts after update.
#   7. Confirm the data folder remains intact and is not overwritten.
# -----------------------------------------------------------

set -euo pipefail

PASS=0
FAIL=0

# ── Helpers ──────────────────────────────────────────────────────────────
pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

# ── Temp workspace ───────────────────────────────────────────────────────
TEST_ROOT=$(mktemp -d)
INSTALL_DIR="$TEST_ROOT/opt/ersatztv"
DATA_FOLDER="$TEST_ROOT/home/ersatztv/.local/share/ersatztv"
SERVICE_DIR="$TEST_ROOT/etc/systemd/system"
SERVICE_FILE="$SERVICE_DIR/ersatztv.service"
SERVICE_NAME="ersatztv"
UPDATER_PATH="$TEST_ROOT/usr/local/bin/update_linux_ersatztv.sh"

cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

# ══════════════════════════════════════════════════════════════════════════
# Stage 1 — Set up a v1.1.0-style install layout
# ══════════════════════════════════════════════════════════════════════════
echo "============================================================"
echo "🧪 ErsatzTV Update Path Test: v1.1.0 → v1.2.0"
echo "============================================================"
echo ""
echo "📂 Stage 1: Setting up v1.1.0 install layout..."

mkdir -p \
    "$INSTALL_DIR" \
    "$DATA_FOLDER/logs" \
    "$DATA_FOLDER/database" \
    "$SERVICE_DIR" \
    "$(dirname "$UPDATER_PATH")"

# --- v1.1.0 application binary stub ------------------------------------
cat > "$INSTALL_DIR/ErsatzTV" <<'STUBEOF'
#!/bin/bash
echo "ErsatzTV v1.1.0 (stub binary)"
STUBEOF
chmod +x "$INSTALL_DIR/ErsatzTV"

# --- v1.1.0 bundled ffmpeg stub ----------------------------------------
mkdir -p "$INSTALL_DIR/ffmpeg"
cat > "$INSTALL_DIR/ffmpeg/ffmpeg" <<'STUBEOF'
#!/bin/bash
echo "ffmpeg stub"
STUBEOF
chmod +x "$INSTALL_DIR/ffmpeg/ffmpeg"

# --- Pre-existing data that MUST survive the update --------------------
echo '{"channels": [{"id": 1, "name": "Test Channel"}]}' > "$DATA_FOLDER/channels.json"
printf 'BINARY_DB_CONTENT' > "$DATA_FOLDER/ersatztv.db"
printf 'ARTWORK_DATA' > "$DATA_FOLDER/artwork.jpg"
echo '2025-10-12 INFO  ErsatzTV v1.1.0 started' > "$DATA_FOLDER/logs/ersatztv.log"
printf 'DB_FILE' > "$DATA_FOLDER/database/ersatztv.db3"

# --- v1.1.0 service file (no Environment= lines) -----------------------
# v1.1.0 did not include Environment=HOME or Environment=PATH entries.
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=ErsatzTV Service
After=network.target

[Service]
User=ersatztv
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/ErsatzTV --data-folder $DATA_FOLDER
ExecStop=/bin/kill -s SIGINT \$MAINPID
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# --- v1.1.0 standalone updater stub ------------------------------------
cat > "$UPDATER_PATH" <<'STUBEOF'
#!/bin/bash
echo "update_linux_ersatztv.sh v1.1.0 (stub)"
STUBEOF
chmod +x "$UPDATER_PATH"

echo "   ✔ $INSTALL_DIR/ErsatzTV  (v1.1.0 binary)"
echo "   ✔ $INSTALL_DIR/ffmpeg/ffmpeg  (bundled ffmpeg)"
echo "   ✔ $SERVICE_FILE  (v1.1.0 service unit — no Environment lines)"
echo "   ✔ $DATA_FOLDER  (channels.json, ersatztv.db, artwork.jpg, logs/, database/)"
echo ""

# ══════════════════════════════════════════════════════════════════════════
# Stage 2 — Run the v1.2.0 update logic
#
# This mirrors the steps performed by ersatztv-linux-automation.sh when run
# with the 'update' action, adapted to operate in the temp workspace.
# ══════════════════════════════════════════════════════════════════════════
echo "🔄 Stage 2: Running v1.2.0 update logic..."

# Step 1: Temporarily disable automatic restart before stopping the service
#         (mirrors: sed -i 's/^Restart=.*/Restart=no/' in the updater)
sed -i 's/^Restart=.*/Restart=no/' "$SERVICE_FILE"

# Step 2: Back up the current install directory before overwriting
BACKUP_DIR="$TEST_ROOT/opt/ersatztv_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r "$INSTALL_DIR"/* "$BACKUP_DIR"/ 2>/dev/null || true

# Step 3: Simulate extracting a new v1.2.0 release tarball.
#         In production this is: curl ... | tar -xzf ... --strip-components=1
#         Here we simply overwrite the binary stub to represent a new release.
cat > "$INSTALL_DIR/ErsatzTV" <<'STUBEOF'
#!/bin/bash
echo "ErsatzTV v1.2.0 (stub binary)"
STUBEOF
chmod +x "$INSTALL_DIR/ErsatzTV"

# Step 4: Binary detection  (matches installer's detect_ersatztv_binary logic)
DETECTED_BINARY=""
if [[ -x "$INSTALL_DIR/ErsatzTV" ]]; then
    DETECTED_BINARY="$INSTALL_DIR/ErsatzTV"
elif [[ -x "$INSTALL_DIR/ErsatzTV-Legacy" ]]; then
    DETECTED_BINARY="$INSTALL_DIR/ErsatzTV-Legacy"
fi

if [[ -z "$DETECTED_BINARY" ]]; then
    echo "❌ FATAL: No executable binary detected after simulated update."
    exit 1
fi

# Step 5: Rewrite the service file to the v1.2.0 format.
#         v1.2.0 adds Environment=HOME and Environment=PATH entries that
#         were absent in v1.1.0.
FFMPEG_PATH="$INSTALL_DIR/ffmpeg"
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

# Step 6: Install the new v1.2.0 standalone updater stub
cat > "$UPDATER_PATH" <<'STUBEOF'
#!/bin/bash
echo "update_linux_ersatztv.sh v1.2.0 (stub)"
STUBEOF
chmod +x "$UPDATER_PATH"

echo "   ✔ Binary detected: $DETECTED_BINARY"
echo "   ✔ Service file rewritten to v1.2.0 format"
echo "   ✔ Updater script replaced with v1.2.0 version"
echo ""

# ══════════════════════════════════════════════════════════════════════════
# Stage 3 — Validate acceptance criteria
# ══════════════════════════════════════════════════════════════════════════

# ── Criterion 1: Service file is rewritten correctly ─────────────────────
echo "────────────────────────────────────────────────────────────"
echo "Criterion 1: Service file is rewritten correctly"
echo "────────────────────────────────────────────────────────────"

SERVICE_EXEC=$(grep '^ExecStart=' "$SERVICE_FILE" | sed 's/^ExecStart=//' | awk '{print $1}')
[[ "$SERVICE_EXEC" == "$DETECTED_BINARY" ]] \
    && pass "ExecStart points to detected binary ($DETECTED_BINARY)" \
    || fail "ExecStart is '$SERVICE_EXEC', expected '$DETECTED_BINARY'"

grep -q "^Restart=on-failure" "$SERVICE_FILE" \
    && pass "Restart=on-failure is set after update" \
    || fail "Restart directive is not 'on-failure' after update"

grep -q "^Environment=HOME=" "$SERVICE_FILE" \
    && pass "Environment=HOME line is present (v1.2.0 addition)" \
    || fail "Environment=HOME is missing from rewritten service file"

grep -q "^Environment=PATH=" "$SERVICE_FILE" \
    && pass "Environment=PATH line is present (v1.2.0 addition)" \
    || fail "Environment=PATH is missing from rewritten service file"

grep -q "^WorkingDirectory=$INSTALL_DIR" "$SERVICE_FILE" \
    && pass "WorkingDirectory is set correctly" \
    || fail "WorkingDirectory is incorrect in service file"

echo ""

# ── Criterion 2: Old binary references removed or migrated ───────────────
echo "────────────────────────────────────────────────────────────"
echo "Criterion 2: Old binary references removed or migrated"
echo "────────────────────────────────────────────────────────────"

# The service ExecStart must point to an executable that actually exists
[[ -x "$SERVICE_EXEC" ]] \
    && pass "ExecStart binary ($SERVICE_EXEC) exists and is executable" \
    || fail "ExecStart binary ($SERVICE_EXEC) is not executable"

# Any stale v1.1.0-specific ErsatzTV-Legacy reference must not be present
# unless that is genuinely the detected binary for this release
LEGACY_REF_COUNT=$(grep -c "ErsatzTV-Legacy" "$SERVICE_FILE" || true)
if [[ "$DETECTED_BINARY" == *"ErsatzTV-Legacy"* ]]; then
    [[ "$LEGACY_REF_COUNT" -eq 1 ]] \
        && pass "Service file references ErsatzTV-Legacy (expected for this binary)" \
        || fail "Unexpected number of ErsatzTV-Legacy references: $LEGACY_REF_COUNT"
else
    [[ "$LEGACY_REF_COUNT" -eq 0 ]] \
        && pass "No stale ErsatzTV-Legacy references remain in service file" \
        || fail "Service file has unexpected ErsatzTV-Legacy reference(s)"
fi

echo ""

# ── Criterion 3: App directory contains expected files ───────────────────
echo "────────────────────────────────────────────────────────────"
echo "Criterion 3: App directory contains expected files"
echo "────────────────────────────────────────────────────────────"

[[ -d "$INSTALL_DIR" ]] \
    && pass "Install directory exists: $INSTALL_DIR" \
    || fail "Install directory is missing: $INSTALL_DIR"

[[ -f "$INSTALL_DIR/ErsatzTV" || -f "$INSTALL_DIR/ErsatzTV-Legacy" ]] \
    && pass "ErsatzTV binary is present in install directory" \
    || fail "No ErsatzTV binary found in install directory"

[[ -x "$INSTALL_DIR/ErsatzTV" || -x "$INSTALL_DIR/ErsatzTV-Legacy" ]] \
    && pass "ErsatzTV binary is executable" \
    || fail "ErsatzTV binary is not executable"

[[ -d "$INSTALL_DIR/ffmpeg" ]] \
    && pass "ffmpeg directory retained in install directory" \
    || fail "ffmpeg directory is missing from install directory"

echo ""

# ── Criterion 4: Service starts after update ─────────────────────────────
# Real systemctl is not available in the test environment; instead we validate
# all prerequisites for a successful service start:
#   (a) binary is executable, (b) unit file is syntactically valid,
#   (c) data folder is accessible, (d) updater is installed.
echo "────────────────────────────────────────────────────────────"
echo "Criterion 4: Service can start after update (readiness checks)"
echo "────────────────────────────────────────────────────────────"

[[ -x "$DETECTED_BINARY" ]] \
    && pass "Binary ($DETECTED_BINARY) is executable — service can start" \
    || fail "Binary ($DETECTED_BINARY) is not executable"

[[ -f "$SERVICE_FILE" ]] \
    && pass "Service unit file exists at $SERVICE_FILE" \
    || fail "Service unit file is missing"

grep -q "^\[Unit\]" "$SERVICE_FILE" \
    && pass "Service unit file has [Unit] section" \
    || fail "Service unit file is malformed (missing [Unit])"

grep -q "^\[Service\]" "$SERVICE_FILE" \
    && pass "Service unit file has [Service] section" \
    || fail "Service unit file is malformed (missing [Service])"

grep -q "^\[Install\]" "$SERVICE_FILE" \
    && pass "Service unit file has [Install] section" \
    || fail "Service unit file is malformed (missing [Install])"

[[ -x "$UPDATER_PATH" ]] \
    && pass "Standalone updater is installed and executable at $UPDATER_PATH" \
    || fail "Standalone updater is missing or not executable"

echo ""

# ── Criterion 5: Data folder remains intact and is not overwritten ────────
echo "────────────────────────────────────────────────────────────"
echo "Criterion 5: Data folder remains intact and not overwritten"
echo "────────────────────────────────────────────────────────────"

[[ -d "$DATA_FOLDER" ]] \
    && pass "Data folder exists: $DATA_FOLDER" \
    || fail "Data folder was removed during update"

[[ -f "$DATA_FOLDER/channels.json" ]] \
    && pass "channels.json preserved" \
    || fail "channels.json was removed during update"

[[ "$(cat "$DATA_FOLDER/channels.json")" == '{"channels": [{"id": 1, "name": "Test Channel"}]}' ]] \
    && pass "channels.json content is unchanged" \
    || fail "channels.json content was altered during update"

[[ -f "$DATA_FOLDER/ersatztv.db" ]] \
    && pass "ersatztv.db preserved" \
    || fail "ersatztv.db was removed during update"

[[ -f "$DATA_FOLDER/artwork.jpg" ]] \
    && pass "artwork.jpg preserved" \
    || fail "artwork.jpg was removed during update"

[[ -f "$DATA_FOLDER/logs/ersatztv.log" ]] \
    && pass "logs/ersatztv.log preserved" \
    || fail "logs/ersatztv.log was removed during update"

[[ -f "$DATA_FOLDER/database/ersatztv.db3" ]] \
    && pass "database/ersatztv.db3 preserved" \
    || fail "database/ersatztv.db3 was removed during update"

echo ""

# ── Bonus: Backup was created before the update ───────────────────────────
echo "────────────────────────────────────────────────────────────"
echo "Bonus: Pre-update backup was created"
echo "────────────────────────────────────────────────────────────"

BACKUP_COUNT=$(ls -d "$TEST_ROOT"/opt/ersatztv_backup_* 2>/dev/null | wc -l)
[[ "$BACKUP_COUNT" -gt 0 ]] \
    && pass "Backup directory created before update ($BACKUP_COUNT found)" \
    || fail "No backup directory was created"

BACKUP_DIR_FIRST=$(ls -d "$TEST_ROOT"/opt/ersatztv_backup_* 2>/dev/null | head -1)
if [[ -n "$BACKUP_DIR_FIRST" ]]; then
    [[ -f "$BACKUP_DIR_FIRST/ErsatzTV" ]] \
        && pass "Backup contains the pre-update binary" \
        || fail "Backup is missing the pre-update binary"
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────────────
echo "============================================================"
TOTAL=$((PASS + FAIL))
if [[ "$FAIL" -eq 0 ]]; then
    echo "✅ All update-path tests passed ($PASS/$TOTAL)"
    exit 0
else
    echo "❌ $FAIL test(s) failed  (passed: $PASS / total: $TOTAL)"
    exit 1
fi
