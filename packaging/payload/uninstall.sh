#!/usr/bin/env bash
#
# uninstall.sh — removes ErsatzTV Linux Automation installation
# -------------------------------------------------------------
# Safely stops services, removes files, and logs all actions.
# Can be invoked directly or via the .run uninstaller flow.
# -------------------------------------------------------------

set -euo pipefail

LOGDIR="/var/log/ersatztv-installer"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/uninstall_$(date +'%Y%m%d_%H%M%S').log"

exec > >(tee -a "$LOGFILE") 2>&1

echo "=========================================="
echo "  ErsatzTV Linux Automation Uninstaller"
echo "=========================================="
echo "Started: $(date)"
echo

# ---------------------------------------------------------
# 1. Stop and disable systemd service if it exists
# ---------------------------------------------------------
SERVICE="ersatztv.service"

if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files | grep -q "^${SERVICE}"; then
    echo "🧩 Stopping and disabling ${SERVICE}..."
    sudo systemctl stop "$SERVICE" 2>/dev/null || true
    sudo systemctl disable "$SERVICE" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/${SERVICE}" 2>/dev/null || true
    sudo systemctl daemon-reload
    echo "✅ ${SERVICE} removed."
  else
    echo "ℹ️  No systemd unit named ${SERVICE} found."
  fi
else
  echo "⚠️  systemctl not found — skipping service cleanup."
fi
echo

# ---------------------------------------------------------
# 2. Remove installed files
# ---------------------------------------------------------
INSTALL_DIR="/opt/ersatztv"
BIN_PATH="/usr/local/bin/ersatztv"

echo "🧹 Removing installation directories..."
sudo rm -rf "$INSTALL_DIR" 2>/dev/null || true
sudo rm -f "$BIN_PATH" 2>/dev/null || true
echo "✅ Files cleaned up."
echo

# ---------------------------------------------------------
# 3. Optionally remove logs
# ---------------------------------------------------------
read -r -p "Do you want to delete installer logs in $LOGDIR? [y/N]: " RESP
if [[ "${RESP,,}" == "y" || "${RESP,,}" == "yes" ]]; then
  sudo rm -rf "$LOGDIR"
  echo "🧾 Logs removed."
else
  echo "🧾 Logs preserved in $LOGDIR."
fi
echo

# ---------------------------------------------------------
# 4. Summary
# ---------------------------------------------------------
echo "------------------------------------------"
echo "Uninstallation complete."
echo "Log file saved to: $LOGFILE"
echo "Finished: $(date)"
echo "------------------------------------------"
echo "✅ ErsatzTV Linux Automation has been fully removed."
echo
exit 0

