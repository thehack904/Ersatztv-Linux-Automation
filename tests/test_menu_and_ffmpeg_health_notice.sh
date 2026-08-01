#!/usr/bin/env bash
set -euo pipefail
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ersatztv-linux-automation.sh"

grep -q '1) develop' "$SCRIPT"
grep -q '2) latest' "$SCRIPT"
grep -q '3) custom' "$SCRIPT"
grep -q 'current and previous three releases' "$SCRIPT"
grep -q '\[0:4\]' "$SCRIPT"
grep -q '\[CURRENT\]' "$SCRIPT"
! grep -q 'Enter custom tag' "$SCRIPT"
! grep -q '3) 26\.4' "$SCRIPT"
! grep -q '4) 26\.3' "$SCRIPT"
! grep -q '6) .*downgrade' "$SCRIPT"
grep -q 'FFmpeg Path:  /opt/ersatztv/ffmpeg/bin/ffmpeg' "$SCRIPT"
grep -q 'FFprobe Path: /opt/ersatztv/ffmpeg/bin/ffprobe' "$SCRIPT"
! grep -qiE 'sqlite3 .*update|update .*ffmpegpath|update .*ffprobepath' "$SCRIPT"
echo '✅ Menu and FFmpeg health-notice regression checks passed.'
