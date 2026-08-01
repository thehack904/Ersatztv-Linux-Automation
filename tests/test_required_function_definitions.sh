#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for script in \
  "$ROOT_DIR/ersatztv-linux-automation.sh" \
  "$ROOT_DIR/packaging/payload/ersatztv-linux-automation.sh"; do
  grep -q '^create_user_and_dirs() {' "$script" || {
    echo "FAIL: create_user_and_dirs is not defined in $script" >&2
    exit 1
  }
  bash -n "$script"
done
echo "PASS: required function definitions are present"
