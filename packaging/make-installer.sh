#!/usr/bin/env bash
#
# make-installer.sh — Build a self-extracting .run installer
# for ErsatzTV-Linux-Automation.
# -----------------------------------------------------------
# Requires: makeself, bash, coreutils, gpg (optional for signing)
# -----------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_DIR="$SCRIPT_DIR/payload"
OUT_FILE="$SCRIPT_DIR/ersatztv-installer.run"

echo "🧩 Building ErsatzTV Linux Automation installer..."

# -----------------------------------------------------------
# 1. Verify payload exists
# -----------------------------------------------------------
if [[ ! -d "$PAYLOAD_DIR" ]]; then
  echo "❌ ERROR: payload directory not found: $PAYLOAD_DIR"
  exit 1
fi

# -----------------------------------------------------------
# 2. Regenerate internal SHA256 manifest for all payload files
# -----------------------------------------------------------
echo "🔍 Generating manifest..."
(
  cd "$PAYLOAD_DIR"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum $(find . -type f -print | sed 's|^\./||') > manifest.sha256
  else
    shasum -a 256 $(find . -type f -print | sed 's|^\./||') > manifest.sha256
  fi
)
echo "✅ Manifest created."

# -----------------------------------------------------------
# 3. Ensure makeself is installed
# -----------------------------------------------------------
if ! command -v makeself >/dev/null 2>&1; then
  echo "📦 Installing makeself..."
  sudo apt-get update -y && sudo apt-get install -y makeself
fi

# -----------------------------------------------------------
# 4. Create the self-extracting installer
# -----------------------------------------------------------
echo "📦 Creating ersatztv-installer.run..."
makeself "$PAYLOAD_DIR" \
  "$OUT_FILE" \
  "ErsatzTV Linux Automation Installer" \
  ./install.sh

# -----------------------------------------------------------
# 5. Generate top-level checksum file
# -----------------------------------------------------------
echo "🔒 Generating top-level checksums..."
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$OUT_FILE" > "$SCRIPT_DIR/checksums.txt"
else
  shasum -a 256 "$OUT_FILE" > "$SCRIPT_DIR/checksums.txt"
fi

# -----------------------------------------------------------
# 6. Completion message
# -----------------------------------------------------------
echo ""
echo "✅ Build complete!"
echo "Output files:"
echo "  • $OUT_FILE"
echo "  • $SCRIPT_DIR/checksums.txt"
echo ""
echo "To verify:"
echo "  sha256sum -c checksums.txt"
echo ""

