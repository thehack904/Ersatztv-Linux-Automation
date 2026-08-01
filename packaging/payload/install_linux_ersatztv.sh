#!/usr/bin/env bash
set -euo pipefail

readonly CANONICAL_SCRIPT="ersatztv-linux-automation.sh"
readonly CANONICAL_URL="https://raw.githubusercontent.com/thehack904/Ersatztv-Linux-Automation/main/${CANONICAL_SCRIPT}"

printf '%s\n' 'Warning: script name "install_linux_ersatztv.sh" is deprecated.' >&2
printf '%s\n' 'Use "ersatztv-linux-automation.sh --install" instead.' >&2

if [[ "$#" -eq 0 ]]; then
    set -- --install
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
local_script="${script_dir}/${CANONICAL_SCRIPT}"

if [[ -f "$local_script" ]]; then
    exec bash "$local_script" "$@"
fi

if ! command -v curl >/dev/null 2>&1; then
    printf '%s\n' 'ERROR: curl is required when the compatibility bootstrapper is run without the canonical script beside it.' >&2
    exit 1
fi

printf '%s\n' "Downloading the canonical lifecycle script from ${CANONICAL_URL}" >&2
exec bash -c 'set -o pipefail; curl -fsSL "$1" | bash -s -- "${@:2}"' bash "$CANONICAL_URL" "$@"
