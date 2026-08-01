#!/usr/bin/env bash
#
# make-installer.sh — Build a self-extracting .run installer
# for ErsatzTV-Linux-Automation.
# -----------------------------------------------------------
# Requires: makeself, bash, coreutils, gpg (optional for signing)
# -----------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PAYLOAD_DIR="$SCRIPT_DIR/payload"
OUT_FILE="$REPO_ROOT/ersatztv-installer.run"
CHECKSUM_FILE="$REPO_ROOT/checksums.txt"

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
    find . -type f ! -name manifest.sha256 -print0 \
      | sort -z \
      | xargs -0 sha256sum > manifest.sha256
  else
    find . -type f ! -name manifest.sha256 -print0 \
      | sort -z \
      | xargs -0 shasum -a 256 > manifest.sha256
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
  (cd "$REPO_ROOT" && sha256sum "$(basename "$OUT_FILE")" > "$(basename "$CHECKSUM_FILE")")
else
  (cd "$REPO_ROOT" && shasum -a 256 "$(basename "$OUT_FILE")" > "$(basename "$CHECKSUM_FILE")")
fi

# -----------------------------------------------------------
# 6. Completion message
# -----------------------------------------------------------
echo ""
echo "✅ Build complete!"
echo "Output files:"
echo "  • $OUT_FILE"
echo "  • $CHECKSUM_FILE"
echo ""
echo "To verify:"
echo "  sha256sum -c checksums.txt"
echo ""

