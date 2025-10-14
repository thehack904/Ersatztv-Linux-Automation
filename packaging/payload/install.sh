#!/usr/bin/env bash
#
# install.sh — internal payload installer
# ---------------------------------------------------------
# This script is executed automatically when users run
# the ersatztv-installer.run self-extracting package.
# ---------------------------------------------------------

set -euo pipefail

LOGDIR="/var/log/ersatztv-installer"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/install_$(date +'%Y%m%d_%H%M%S').log"

# Redirect all output to log and console
exec > >(tee -a "$LOGFILE") 2>&1

echo "=========================================="
echo "  ErsatzTV Linux Automation Installer"
echo "=========================================="
echo "Started: $(date)"
echo

# ---------------------------------------------------------
# 1. Verify payload integrity (manifest.sha256)
# ---------------------------------------------------------
if [[ -f "./manifest.sha256" ]]; then
  echo "🔍 Verifying payload integrity..."
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c manifest.sha256
  else
    shasum -a 256 -c manifest.sha256
  fi
  echo "✅ Payload integrity check passed."
else
  echo "⚠️  Warning: manifest.sha256 not found — skipping integrity check."
fi
echo

# ---------------------------------------------------------
# 2. Ensure main installer script exists
# ---------------------------------------------------------
INSTALLER="./install_linux_ersatztv.sh"

if [[ ! -x "$INSTALLER" ]]; then
  echo "❌ ERROR: $INSTALLER not found or not executable."
  exit 1
fi

# ---------------------------------------------------------
# 3. Run the main installer with any arguments passed
# ---------------------------------------------------------
echo "🚀 Running ErsatzTV Linux Automation installer..."
"$INSTALLER" "$@"
echo
echo "✅ install_linux_ersatztv.sh completed successfully."
echo

# ---------------------------------------------------------
# 4. Wrap up and log summary
# ---------------------------------------------------------
echo "------------------------------------------"
echo "Installation log saved to:"
echo "  $LOGFILE"
echo "------------------------------------------"
echo "✅ All tasks completed.  Exiting normally."
echo "Finished: $(date)"
echo
exit 0

