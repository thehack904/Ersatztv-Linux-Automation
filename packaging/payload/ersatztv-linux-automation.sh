#!/bin/bash
#
# ersatztv-linux-automation.sh
# ---------------------------------------------------------
# Unified installer, updater, and uninstaller for ErsatzTV.
# Compatible with x64 and ARM64 Linux distributions.
# ---------------------------------------------------------
AUTOMATION_VERSION="1.3.0"

set -e

SERVICE_NAME="ersatztv"
INSTALL_DIR="/opt/ersatztv"
DATA_FOLDER="/home/ersatztv/.local/share/ersatztv"
GITHUB_REPO="ErsatzTV/legacy"
FFMPEG_REPO="ErsatzTV/ErsatzTV-ffmpeg"
FFMPEG_TAG_FILE="$INSTALL_DIR/.installed_ffmpeg_version"
KNOWN_FFMPEG_COMPATIBILITY=(
    "v26.7.0:8.1.2"
    "v25.2.0:7.1.1"
)
AUTOMATION_STATE_DIR="/var/lib/ersatztv-linux-automation"
COMPATIBILITY_CACHE_DIR="$AUTOMATION_STATE_DIR/compatibility"
AUTOMATION_CMD_PATH="/usr/local/sbin/ersatztv-linux-automation"
LEGACY_AUTOMATION_CMD_PATH="/usr/local/bin/ersatztv-linux-automation"
INSTALLER_COMPAT_PATH="/usr/local/bin/install_linux_ersatztv.sh"
UPDATER_PATH="/usr/local/bin/update_linux_ersatztv.sh"
LOCK_FILE="/run/lock/ersatztv-linux-automation.lock"
LOCK_PID_FILE="/run/lock/ersatztv-linux-automation.pid"
LOCK_FD=9
LOCK_METHOD=""
ORIGINAL_RESTART_POLICY=""
SERVICE_WAS_ACTIVE=false
SERVICE_WAS_ENABLED=false
SERVICE_UNIT_EXISTS=false
TRANSACTION_BACKUP_DIR=""
STAGING_DIR=""
RAW_SCRIPT_URL="https://raw.githubusercontent.com/thehack904/ErsatzTV-Linux-Automation/main/ersatztv-linux-automation.sh"
INVOCATION_NAME="$(basename "$0")"
ACTION=""
PURGE_FLAG=false
RETROIPTVGUIDE_FLAG=false
INVALID_ARGUMENT_MESSAGE=""

# --- Version selection -------------------------------------------------------
# The default tag matches the recommended GHCR image: ghcr.io/ersatztv/legacy:develop
DEFAULT_ERSATZTV_TAG="develop"
ERSATZTV_IMAGE_BASE="ghcr.io/ersatztv/legacy"
ERSATZTV_TAG_FILE="$INSTALL_DIR/.installed_ersatztv_tag"
SELECTED_TAG=""
RESOLVED_ERSATZTV_TAG=""
RESOLVED_ERSATZTV_RELEASE_URL=""
RESOLVED_FFMPEG_VERSION=""
RESOLVED_FFMPEG_SOURCE=""
RESOLVED_FFMPEG_CONFIDENCE=""
RESOLVED_FFMPEG_RELEASE_URL=""

# --- Detect architecture -----------------------------------------------------
ARCH=$(uname -m)
ARCH_SUFFIX=""
FFMPEG_ARCH_SUFFIX=""
ARCH_SUPPORTED=true
case "$ARCH" in
    x86_64|amd64)
        ARCH_SUFFIX="x64"
        FFMPEG_ARCH_SUFFIX="linux64"
        ;;
    aarch64|arm64)
        ARCH_SUFFIX="arm64"
        FFMPEG_ARCH_SUFFIX="linuxarm64"
        ;;
    *)
        ARCH_SUPPORTED=false
        ;;
esac

# --- RHEL / Fedora Compatibility ---------------------------------------------
if [[ -f /etc/fedora-release || -f /etc/redhat-release ]]; then
    echo "🔹 Fedora/RHEL system detected. Ensuring prerequisites..."
    PKG_MGR=$(command -v dnf || command -v yum)
    $PKG_MGR install -y curl tar git 2>/dev/null || true

    # Use correct nologin path (differs on some Fedora/RHEL systems)
    NOLOGIN_PATH=$(command -v nologin || echo "/sbin/nologin")

    # Handle SELinux contexts if enabled
    if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" == "Enforcing" ]]; then
        echo "🔸 SELinux is enforcing — permissions will be adjusted post-install."
        SELINUX_ENFORCING=true
    else
        SELINUX_ENFORCING=false
    fi
else
    NOLOGIN_PATH="/usr/sbin/nologin"
    SELINUX_ENFORCING=false
fi

# --- Functions ---------------------------------------------------------------

show_usage() {
    local exit_code="${1:-1}"
    echo "ErsatzTV Linux Automation (Legacy Installer / Updater / Uninstaller)"
    echo "This tool supports ErsatzTV Legacy only; ErsatzTV Next is not supported."
    echo
    echo "Usage:"
    echo "  sudo ersatztv-linux-automation --install [--retroiptvguide]"
    echo "  sudo ersatztv-linux-automation --upgrade [--retroiptvguide]"
    echo "  sudo ersatztv-linux-automation --repair"
    echo "  sudo ersatztv-linux-automation --uninstall [--purge] [--retroiptvguide]"
    echo "  sudo ersatztv-linux-automation --version"
    echo "  sudo ersatztv-linux-automation --help"
    echo
    echo "Primary actions (exactly one required):"
    echo "  --install, --upgrade, --repair, --uninstall, --version, --help"
    echo
    echo "Modifiers:"
    echo "  --retroiptvguide  Install RetroIPTVGuide after ErsatzTV setup"
    echo "  --purge           Remove all data under $DATA_FOLDER during uninstall"
    echo
    echo "Compatibility (deprecated):"
    echo "  install   -> --install"
    echo "  update    -> --upgrade"
    echo "  uninstall -> --uninstall"
    echo
    echo "Version selection:"
    echo "  Set the ERSATZTV_VERSION environment variable to skip the interactive prompt."
    echo "  Examples:"
    echo "    ERSATZTV_VERSION=develop sudo -E ersatztv-linux-automation --install"
    echo "    ERSATZTV_VERSION=v26.7.1 sudo -E ersatztv-linux-automation --install"
    echo "    ERSATZTV_VERSION=v26.7.1 sudo -E ersatztv-linux-automation --upgrade"
    echo
    echo "  Menu choices: develop (default), latest, or custom."
    echo "  Any valid GitHub release tag may still be supplied through custom selection or ERSATZTV_VERSION."
    exit "$exit_code"
}

log_info() { echo "ℹ️  $*"; }
log_warn() { echo "⚠️  $*"; }
log_error() { echo "❌ $*" >&2; }

FFMPEG_HEALTH_WARNING=false
FFMPEG_HEALTH_DETAIL=""

print_version() {
    echo "ErsatzTV Linux Automation $AUTOMATION_VERSION"
}

map_deprecated_positional_action() {
    case "$1" in
        install)
            echo "Warning: positional action \"install\" is deprecated." >&2
            echo "Use \"--install\" instead." >&2
            echo "install"
            ;;
        update)
            echo "Warning: positional action \"update\" is deprecated." >&2
            echo "Use \"--upgrade\" instead." >&2
            echo "upgrade"
            ;;
        uninstall)
            echo "Warning: positional action \"uninstall\" is deprecated." >&2
            echo "Use \"--uninstall\" instead." >&2
            echo "uninstall"
            ;;
        *)
            return 1
            ;;
    esac
}

parse_arguments() {
    local -a parsed_actions=()
    local mapped_action
    local arg

    for arg in "$@"; do
        case "$arg" in
            --install) parsed_actions+=("install") ;;
            --upgrade) parsed_actions+=("upgrade") ;;
            --repair) parsed_actions+=("repair") ;;
            --uninstall) parsed_actions+=("uninstall") ;;
            --version) parsed_actions+=("version") ;;
            --help) parsed_actions+=("help") ;;
            --purge) PURGE_FLAG=true ;;
            --retroiptvguide) RETROIPTVGUIDE_FLAG=true ;;
            install|update|uninstall)
                mapped_action=$(map_deprecated_positional_action "$arg")
                parsed_actions+=("$mapped_action")
                ;;
            repair)
                parsed_actions+=("repair")
                ;;
            *)
                INVALID_ARGUMENT_MESSAGE="Unknown argument: $arg"
                ;;
        esac
    done

    if [[ -z "$INVALID_ARGUMENT_MESSAGE" ]]; then
        if [[ ${#parsed_actions[@]} -eq 0 ]]; then
            case "$INVOCATION_NAME" in
                install_linux_ersatztv.sh)
                    log_warn "Warning: compatibility command \"install_linux_ersatztv.sh\" is deprecated."
                    log_warn "Use \"ersatztv-linux-automation --install\" instead."
                    ACTION="install"
                    ;;
                update_linux_ersatztv.sh)
                    log_warn "Warning: compatibility command \"update_linux_ersatztv.sh\" is deprecated."
                    log_warn "Use \"ersatztv-linux-automation --upgrade\" instead."
                    ACTION="upgrade"
                    ;;
                *)
                    ACTION=""
                    ;;
            esac
        elif [[ ${#parsed_actions[@]} -eq 1 ]]; then
            ACTION="${parsed_actions[0]}"
        else
            INVALID_ARGUMENT_MESSAGE="Conflicting actions provided. Specify exactly one primary action."
        fi
    fi
}

validate_arguments() {
    if [[ -n "$INVALID_ARGUMENT_MESSAGE" ]]; then
        log_error "$INVALID_ARGUMENT_MESSAGE"
        show_usage 1
    fi

    if [[ -z "$ACTION" ]]; then
        show_usage 1
    fi

    case "$ACTION" in
        install|upgrade|repair|uninstall|version|help) ;;
        *)
            log_error "Invalid action: $ACTION"
            show_usage 1
            ;;
    esac

    if [[ "$PURGE_FLAG" == true && "$ACTION" != "uninstall" ]]; then
        log_error "--purge can only be used with --uninstall."
        show_usage 1
    fi

    if [[ "$RETROIPTVGUIDE_FLAG" == true && "$ACTION" != "install" && "$ACTION" != "upgrade" && "$ACTION" != "uninstall" ]]; then
        log_error "--retroiptvguide is only supported with --install, --upgrade, or --uninstall."
        show_usage 1
    fi
}

validate_supported_architecture() {
    if [[ "$ARCH_SUPPORTED" != true ]]; then
        log_error "Unsupported architecture '$ARCH'. Supported architectures: x86_64/amd64 and aarch64/arm64."
        exit 1
    fi
}

acquire_lock() {
    mkdir -p /run/lock
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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "❌ This script must be run as root (sudo)."
        exit 1
    fi
    # Make sure /opt is usable by service users
    if [[ "$(stat -c %a /opt 2>/dev/null || echo 700)" -lt 755 ]]; then
        echo "🔧 Fixing /opt permissions..."
        chown root:root /opt 2>/dev/null || true
        chmod 755 /opt 2>/dev/null || true
    fi
}

# --- Stage 1: Version Check ---------------------------------------------------
check_existing_version() {
    local binary_found=false
    if [[ -f "$INSTALL_DIR/ErsatzTV" || -f "$INSTALL_DIR/ErsatzTV-Legacy" ]]; then
        binary_found=true
    fi

    if [[ "$binary_found" == true ]]; then
        echo "🔍 ErsatzTV is currently installed."

        # Prefer the tag file written by this installer on previous runs
        if [[ -f "$ERSATZTV_TAG_FILE" || -f "$INSTALL_DIR/.installed_tag" ]]; then
            local current_tag
            current_tag=$(cat "$ERSATZTV_TAG_FILE" 2>/dev/null || cat "$INSTALL_DIR/.installed_tag" 2>/dev/null || echo "")
            if [[ -n "$current_tag" ]]; then
                echo "   Installed tag : $current_tag  (${ERSATZTV_IMAGE_BASE}:${current_tag})"
            fi
        else
            # Fall back to journal-based version detection for pre-v1.2.1 installs
            local log_version
            log_version=$(journalctl -u $SERVICE_NAME --no-pager -n 500 2>/dev/null | grep "ErsatzTV version" | tail -n 1 | awk '{print $NF}' || echo "")
            if [[ -n "$log_version" ]]; then
                echo "   Installed version: $log_version"
            else
                echo "   ⚠️  Cannot determine installed version from logs."
            fi
        fi
    fi
}

has_managed_installation() {
    [[ -x "$INSTALL_DIR/ErsatzTV" || -x "$INSTALL_DIR/ErsatzTV-Legacy" ]]
}

# --- Stage 2: Version selection -----------------------------------------------
# Fetch and display the newest four published ErsatzTV releases.
select_recent_ersatztv_release() {
    local releases_json=""
    local -a release_tags=()
    local -a prerelease_flags=()

    echo ""
    echo "🔍 Fetching the current and previous three ErsatzTV releases..."

    if ! releases_json=$(curl -fsSL --max-time 15 \
        "https://api.github.com/repos/$GITHUB_REPO/releases?per_page=10" 2>/dev/null); then
        echo "❌ Unable to retrieve ErsatzTV releases from GitHub."
        return 1
    fi

    mapfile -t release_tags < <(
        jq -r '[.[] | select(.draft == false)][0:4][] | .tag_name' <<<"$releases_json"
    )
    mapfile -t prerelease_flags < <(
        jq -r '[.[] | select(.draft == false)][0:4][] | .prerelease' <<<"$releases_json"
    )

    if (( ${#release_tags[@]} == 0 )); then
        echo "❌ GitHub returned no published ErsatzTV releases."
        return 1
    fi

    echo ""
    echo "📦 Select a specific ErsatzTV release:"
    local index label
    for index in "${!release_tags[@]}"; do
        label=""
        if (( index == 0 )); then
            label="  [CURRENT]"
        fi
        if [[ "${prerelease_flags[$index]:-false}" == "true" ]]; then
            label+="  [PRERELEASE]"
        fi
        printf '   %d) %s%s\n' "$((index + 1))" "${release_tags[$index]}" "$label"
    done
    echo "   B) Back to the previous menu"
    echo "   Q) Cancel without making changes"
    echo ""

    local release_choice=""
    read -rp "Enter choice [1-${#release_tags[@]}, B, Q, or press Enter for current '${release_tags[0]}']: " release_choice
    release_choice="${release_choice:-1}"

    case "${release_choice,,}" in
        b|back)
            return 2
            ;;
        q|quit|cancel)
            echo "ℹ️  Operation cancelled. No changes were made."
            exit 0
            ;;
    esac

    if [[ ! "$release_choice" =~ ^[0-9]+$ ]] || \
       (( release_choice < 1 || release_choice > ${#release_tags[@]} )); then
        echo "⚠️  Invalid release selection. Returning to the previous menu."
        return 2
    fi

    SELECTED_TAG="${release_tags[$((release_choice - 1))]}"
}

select_ersatztv_version() {
    # Non-interactive: honour the ERSATZTV_VERSION environment variable.
    if [[ -n "${ERSATZTV_VERSION:-}" ]]; then
        local env_tag="${ERSATZTV_VERSION// /}"
        if [[ -z "$env_tag" ]]; then
            echo "⚠️  ERSATZTV_VERSION is set but blank — using default: $DEFAULT_ERSATZTV_TAG"
            SELECTED_TAG="$DEFAULT_ERSATZTV_TAG"
        else
            SELECTED_TAG="$env_tag"
            echo "ℹ️  ERSATZTV_VERSION is set — using tag: $SELECTED_TAG  (${ERSATZTV_IMAGE_BASE}:${SELECTED_TAG})"
        fi
        return
    fi

    local installed_tag=""
    if [[ -f "$ERSATZTV_TAG_FILE" || -f "$INSTALL_DIR/.installed_tag" ]]; then
        installed_tag=$(cat "$ERSATZTV_TAG_FILE" 2>/dev/null || cat "$INSTALL_DIR/.installed_tag" 2>/dev/null || echo "")
    fi

    echo ""
    while true; do
        echo "📦 Select which ErsatzTV Legacy version to install:"
        echo "   1) develop  — latest development build  [DEFAULT, recommended]"
        echo "   2) latest   — latest stable GitHub release"
        echo "   3) custom   — choose from the current and previous three releases"
        echo "   Q) cancel   — exit without making changes"
        echo ""
        if [[ -n "$installed_tag" ]]; then
            echo "   Currently installed: $installed_tag"
            echo ""
        fi

        local choice=""
        if [ -t 0 ]; then
            read -rp "Enter choice [1-3, Q, or press Enter for default 'develop']: " choice
        fi
        choice="${choice:-1}"

        case "${choice,,}" in
            1|develop)
                SELECTED_TAG="develop"
                break
                ;;
            2|latest)
                SELECTED_TAG="latest"
                break
                ;;
            3|custom)
                if [ -t 0 ]; then
                    local custom_status=0
                    select_recent_ersatztv_release || custom_status=$?
                    if (( custom_status == 0 )); then
                        break
                    elif (( custom_status == 2 )); then
                        echo ""
                        continue
                    else
                        echo "⚠️  Release list unavailable. Returning to the previous menu."
                        echo ""
                        continue
                    fi
                else
                    echo "⚠️  Non-interactive mode with no ERSATZTV_VERSION set — using default: $DEFAULT_ERSATZTV_TAG"
                    SELECTED_TAG="$DEFAULT_ERSATZTV_TAG"
                    break
                fi
                ;;
            q|quit|cancel)
                echo "ℹ️  Operation cancelled. No changes were made."
                exit 0
                ;;
            *)
                echo "⚠️  Invalid selection. Please choose 1, 2, 3, or Q."
                echo ""
                ;;
        esac
    done

    echo "✅ Selected tag: $SELECTED_TAG  (${ERSATZTV_IMAGE_BASE}:${SELECTED_TAG})"
}

create_user_and_dirs() {
    if ! id -u ersatztv >/dev/null 2>&1; then
        echo "🔹 Creating ersatztv system user..."
        useradd -r -m -d /home/ersatztv -s "$NOLOGIN_PATH" ersatztv
    else
        echo "ℹ️ ersatztv user already exists."
    fi

    # Create home and data directories with the required ownership and modes.
    install -d -o ersatztv -g ersatztv -m 750 /home/ersatztv
    install -d -o ersatztv -g ersatztv -m 700 /home/ersatztv/.local
    install -d -o ersatztv -g ersatztv -m 700 /home/ersatztv/.local/share
    install -d -o ersatztv -g ersatztv -m 700 "$DATA_FOLDER"
    install -d -o ersatztv -g ersatztv -m 700 "$DATA_FOLDER/logs"
    install -d -o ersatztv -g ersatztv -m 755 "$INSTALL_DIR"
}

_normalize_github_tag() {
    local tag="$1"
    if [[ "$tag" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "v${tag}.0"
    else
        echo "$tag"
    fi
}

# Returns 0 (true) if $1 looks like a versioned release tag (e.g. 26.4, v26.4.0).
# Returns 1 for pseudo-tags like develop/latest.
_is_versioned_tag() {
    [[ "$1" =~ ^v?[0-9]+\.[0-9]+ ]]
}

# Returns 0 (true) if version tag $1 is strictly older than version tag $2.
# Comparison uses major.minor integers; patch component is ignored.
# Returns 1 when either tag is a pseudo-tag (develop/latest) or not a version.
_tag_is_older_than() {
    local a="$1" b="$2"
    _is_versioned_tag "$a" || return 1
    _is_versioned_tag "$b" || return 1
    # Strip leading 'v', then extract major and minor (ignore patch)
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

_normalize_version_tag() {
    local v="$1"
    v="${v#v}"
    v="${v#V}"
    echo "$v"
}

_version_compare() {
    local a b i
    local -a av bv
    a=$(_normalize_version_tag "$1")
    b=$(_normalize_version_tag "$2")
    IFS='.' read -r -a av <<< "$a"
    IFS='.' read -r -a bv <<< "$b"
    for i in 0 1 2; do
        local ai="${av[$i]:-0}"
        local bi="${bv[$i]:-0}"
        if (( ai < bi )); then
            echo "-1"
            return
        elif (( ai > bi )); then
            echo "1"
            return
        fi
    done
    echo "0"
}

known_ffmpeg_version_for_ersatztv() {
    local normalized
    normalized=$(_normalize_github_tag "$1")
    case "$normalized" in
        v26.7.0) echo "8.1.2" ;;
        v25.2.0) echo "7.1.1" ;;
        *) return 1 ;;
    esac
}

_compatibility_cache_file() {
    local ersatztv_tag="$1"
    printf '%s/%s\n' "$COMPATIBILITY_CACHE_DIR" "$ersatztv_tag"
}

_read_cached_ffmpeg_requirement() {
    local ersatztv_tag="$1"
    local cache_file cached_release cached_ffmpeg cached_source cached_confidence
    cache_file=$(_compatibility_cache_file "$ersatztv_tag")
    [[ -f "$cache_file" ]] || return 1
    cached_release=$(grep -E '^ERSATZTV_VERSION=' "$cache_file" | cut -d '=' -f 2-)
    cached_ffmpeg=$(grep -E '^FFMPEG_VERSION=' "$cache_file" | cut -d '=' -f 2-)
    cached_source=$(grep -E '^SOURCE=' "$cache_file" | cut -d '=' -f 2-)
    cached_confidence=$(grep -E '^CONFIDENCE=' "$cache_file" | cut -d '=' -f 2-)
    if [[ "$cached_release" != "$ersatztv_tag" || -z "$cached_ffmpeg" || -z "$cached_source" || -z "$cached_confidence" ]]; then
        return 1
    fi
    RESOLVED_ERSATZTV_TAG="$cached_release"
    RESOLVED_FFMPEG_VERSION="$cached_ffmpeg"
    RESOLVED_FFMPEG_SOURCE="$cached_source"
    RESOLVED_FFMPEG_CONFIDENCE="$cached_confidence"
    RESOLVED_FFMPEG_RELEASE_URL="$(grep -E '^FFMPEG_RELEASE_URL=' "$cache_file" | cut -d '=' -f 2-)"
    RESOLVED_ERSATZTV_RELEASE_URL="$(grep -E '^RELEASE_URL=' "$cache_file" | cut -d '=' -f 2-)"
    return 0
}

_write_cached_ffmpeg_requirement() {
    local cache_file
    mkdir -p "$COMPATIBILITY_CACHE_DIR"
    cache_file=$(_compatibility_cache_file "$RESOLVED_ERSATZTV_TAG")
    cat > "$cache_file" <<EOF
ERSATZTV_VERSION=$RESOLVED_ERSATZTV_TAG
FFMPEG_VERSION=$RESOLVED_FFMPEG_VERSION
SOURCE=$RESOLVED_FFMPEG_SOURCE
CONFIDENCE=$RESOLVED_FFMPEG_CONFIDENCE
RELEASE_URL=$RESOLVED_ERSATZTV_RELEASE_URL
FFMPEG_RELEASE_URL=$RESOLVED_FFMPEG_RELEASE_URL
RESOLVED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

_fetch_selected_release_json() {
    local requested_tag="$1"
    case "$requested_tag" in
        develop)
            curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases?per_page=50" \
                | jq -c '[.[] | select((.draft // false) == false)][0]'
            ;;
        latest)
            curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | jq -c '.'
            ;;
        *)
            curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases/tags/$(_normalize_github_tag "$requested_tag")" | jq -c '.'
            ;;
    esac
}

_extract_ffmpeg_link_version() {
    local body="$1"
    local link
    link=$(printf '%s\n' "$body" | grep -Eio 'https://github\.com/ErsatzTV/ErsatzTV-ffmpeg/releases/tag/[vV]?[0-9]+(\.[0-9]+){1,2}' | head -n 1 || true)
    [[ -n "$link" ]] || return 1
    printf '%s\n' "${link##*/}" | sed 's/^[vV]//'
}

_extract_ffmpeg_text_version() {
    local body="$1" line version to_version candidate
    while IFS= read -r line; do
        [[ "${line,,}" == *ffmpeg* ]] || continue
        if [[ ! "${line,,}" =~ (require|requires|required|bundled|upgrade|upgraded|updated|ersatztv-ffmpeg) ]]; then
            continue
        fi
        to_version=$(printf '%s\n' "$line" | grep -Eio '(to|->)[[:space:]]*[vV]?[0-9]+(\.[0-9]+){1,2}' | head -n 1 | grep -Eo '[vV]?[0-9]+(\.[0-9]+){1,2}' || true)
        if [[ -n "$to_version" ]]; then
            printf '%s\n' "$to_version" | sed 's/^[vV]//'
            return 0
        fi
        candidate=$(printf '%s\n' "$line" | grep -Eio '(ersatztv-ffmpeg|ffmpeg)[^0-9vV]*[vV]?[0-9]+(\.[0-9]+){1,2}' | head -n 1 || true)
        version=$(printf '%s\n' "$candidate" | grep -Eo '[vV]?[0-9]+(\.[0-9]+){1,2}' | head -n 1 || true)
        if [[ -n "$version" ]]; then
            printf '%s\n' "$version" | sed 's/^[vV]//'
            return 0
        fi
    done <<< "$body"
    return 1
}

_extract_ffmpeg_asset_version() {
    local release_json="$1"
    local matches
    matches=$(printf '%s\n' "$release_json" \
        | jq -r '.assets[]?.name // empty' \
        | awk 'BEGIN{IGNORECASE=1} /ffmpeg/ && /linux/ {print}' \
        | grep -Eo '[vV]?[0-9]+(\.[0-9]+){1,2}' \
        | sed 's/^[vV]//' \
        | sort -u || true)
    if [[ "$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l)" -eq 1 ]]; then
        printf '%s\n' "$matches" | sed '/^$/d'
        return 0
    fi
    return 1
}

_detect_release_ffmpeg_requirement() {
    local release_json="$1"
    local body link_version text_version asset_version
    body=$(printf '%s\n' "$release_json" | jq -r '.body // ""')
    if link_version=$(_extract_ffmpeg_link_version "$body"); then
        RESOLVED_FFMPEG_VERSION="$link_version"
        RESOLVED_FFMPEG_SOURCE="release-notes-link"
        RESOLVED_FFMPEG_CONFIDENCE="explicit"
        RESOLVED_FFMPEG_RELEASE_URL="https://github.com/$FFMPEG_REPO/releases/tag/$link_version"
        return 0
    fi
    if text_version=$(_extract_ffmpeg_text_version "$body"); then
        RESOLVED_FFMPEG_VERSION="$text_version"
        RESOLVED_FFMPEG_SOURCE="release-notes-text"
        RESOLVED_FFMPEG_CONFIDENCE="explicit"
        RESOLVED_FFMPEG_RELEASE_URL="https://github.com/$FFMPEG_REPO/releases/tag/$text_version"
        return 0
    fi
    if asset_version=$(_extract_ffmpeg_asset_version "$release_json"); then
        RESOLVED_FFMPEG_VERSION="$asset_version"
        RESOLVED_FFMPEG_SOURCE="release-asset"
        RESOLVED_FFMPEG_CONFIDENCE="explicit"
        RESOLVED_FFMPEG_RELEASE_URL="https://github.com/$FFMPEG_REPO/releases/tag/$asset_version"
        return 0
    fi
    return 1
}

resolve_ersatztv_ffmpeg_requirement() {
    local requested_tag="$1"
    local release_json release_tag known_version
    local all_releases idx inherited_release inherited_version inherited_source

    release_json=$(_fetch_selected_release_json "$requested_tag" 2>/dev/null || true)
    if [[ -z "$release_json" || "$release_json" == "null" ]]; then
        if _is_versioned_tag "$requested_tag" && _read_cached_ffmpeg_requirement "$(_normalize_github_tag "$requested_tag")"; then
            log_warn "GitHub release lookup failed. Using cached compatibility for $RESOLVED_ERSATZTV_TAG."
            return 0
        fi
        log_error "Unable to retrieve selected ErsatzTV release metadata for '$requested_tag'."
        return 1
    fi

    release_tag=$(printf '%s\n' "$release_json" | jq -r '.tag_name // empty')
    RESOLVED_ERSATZTV_TAG="$release_tag"
    RESOLVED_ERSATZTV_RELEASE_URL=$(printf '%s\n' "$release_json" | jq -r '.html_url // empty')

    log_info "Inspecting ErsatzTV release: $release_tag"

    if _detect_release_ffmpeg_requirement "$release_json"; then
        return 0
    fi

    if known_version=$(known_ffmpeg_version_for_ersatztv "$release_tag" 2>/dev/null); then
        RESOLVED_FFMPEG_VERSION="$known_version"
        RESOLVED_FFMPEG_SOURCE="known-mapping"
        RESOLVED_FFMPEG_CONFIDENCE="mapped"
        RESOLVED_FFMPEG_RELEASE_URL="https://github.com/$FFMPEG_REPO/releases/tag/$known_version"
        return 0
    fi

    all_releases=$(curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases?per_page=100" 2>/dev/null || true)
    if [[ -n "$all_releases" ]]; then
        idx=$(printf '%s\n' "$all_releases" | jq -r --arg tag "$release_tag" 'map(.tag_name) | index($tag)')
        if [[ "$idx" != "null" ]]; then
            while IFS= read -r inherited_release; do
                [[ -n "$inherited_release" ]] || continue
                local candidate_tag
                candidate_tag=$(printf '%s\n' "$inherited_release" | jq -r '.tag_name // empty')
                if [[ "$candidate_tag" == "$release_tag" ]]; then
                    continue
                fi
                if _detect_release_ffmpeg_requirement "$inherited_release" 2>/dev/null; then
                    inherited_version="$RESOLVED_FFMPEG_VERSION"
                    inherited_source="$RESOLVED_FFMPEG_SOURCE"
                    RESOLVED_FFMPEG_VERSION="$inherited_version"
                    RESOLVED_FFMPEG_SOURCE="inherited"
                    RESOLVED_FFMPEG_CONFIDENCE="inherited"
                    log_info "No explicit FFmpeg change in $release_tag. Inheriting $inherited_version from $candidate_tag ($inherited_source)."
                    return 0
                fi
                if known_version=$(known_ffmpeg_version_for_ersatztv "$candidate_tag" 2>/dev/null); then
                    RESOLVED_FFMPEG_VERSION="$known_version"
                    RESOLVED_FFMPEG_SOURCE="inherited"
                    RESOLVED_FFMPEG_CONFIDENCE="inherited"
                    RESOLVED_FFMPEG_RELEASE_URL="https://github.com/$FFMPEG_REPO/releases/tag/$known_version"
                    log_info "No explicit FFmpeg change in $release_tag. Inheriting $known_version from $candidate_tag (known mapping)."
                    return 0
                fi
            done < <(printf '%s\n' "$all_releases" | jq -c --argjson start "$idx" '.[$start:][]')
        fi
    fi

    if _read_cached_ffmpeg_requirement "$release_tag"; then
        log_warn "Using cached compatibility for $release_tag due to unresolved release-note requirement."
        return 0
    fi

    RESOLVED_FFMPEG_SOURCE="unknown"
    RESOLVED_FFMPEG_CONFIDENCE="unknown"
    RESOLVED_FFMPEG_VERSION=""
    return 1
}

_resolve_required_ffmpeg_tag() {
    local ersatztv_tag="$1"
    resolve_ersatztv_ffmpeg_requirement "$ersatztv_tag" || return 1
    [[ -n "$RESOLVED_FFMPEG_VERSION" ]]
}

# Fetches the GitHub release tag immediately older than $1 in the ErsatzTV/legacy
# releases list. Returns the user-friendly short form (e.g. "26.3"), or empty string
# when no previous release is found or the tag is a pseudo-tag.
_fetch_previous_github_tag() {
    local current_tag="$1"
    _is_versioned_tag "$current_tag" || { echo ""; return; }
    local resolved
    resolved=$(_normalize_github_tag "$current_tag")
    local all_tags
    all_tags=$(curl -s --max-time 8 "https://api.github.com/repos/$GITHUB_REPO/releases" \
        | grep '"tag_name"' | cut -d '"' -f 4) || true
    [[ -z "$all_tags" ]] && { echo ""; return; }
    local found=false
    while IFS= read -r tag; do
        if [[ "$found" == true ]]; then
            # Convert GitHub tag format (v26.3.0) to user-friendly form (26.3)
            if [[ "$tag" =~ ^v([0-9]+\.[0-9]+)\.0$ ]]; then
                echo "${BASH_REMATCH[1]}"
            else
                echo "$tag"
            fi
            return
        fi
        [[ "$tag" == "$resolved" ]] && found=true
    done <<< "$all_tags"
    echo ""
}

# Creates a timestamped backup of the ErsatzTV data folder under /opt/.
# Called automatically before a downgrade to protect the user's database.
backup_data_folder() {
    local backup_dir="/opt/ersatztv_data_backup_$(date +%Y%m%d_%H%M%S)"
    echo "📦 Backing up ErsatzTV data to $backup_dir ..."
    cp -a "$DATA_FOLDER" "$backup_dir" 2>/dev/null || true
    if [[ -d "$backup_dir" ]]; then
        echo "✅ Data backup created at $backup_dir"
        echo "   To restore: sudo cp -a ${backup_dir}/. ${DATA_FOLDER}/"
    else
        echo "⚠️  Data backup could not be created — proceeding with downgrade anyway."
    fi
}

download_ersatztv() {
    local tag="${SELECTED_TAG:-$DEFAULT_ERSATZTV_TAG}"
    echo "🔹 Downloading ErsatzTV tag '$tag' for Linux ($ARCH_SUFFIX)..."

    # Detect downgrade and back up data before replacing binaries
    if [[ -f "$ERSATZTV_TAG_FILE" ]]; then
        local installed_tag
        installed_tag=$(cat "$ERSATZTV_TAG_FILE" 2>/dev/null || echo "")
        if [[ -n "$installed_tag" ]] && _tag_is_older_than "$tag" "$installed_tag"; then
            echo ""
            echo "  ⬇️  DOWNGRADE DETECTED: $installed_tag → $tag"
            echo "  ⚠️  Your ErsatzTV database schema may not be backward-compatible."
            echo "  📦 Creating a backup of your data folder before proceeding..."
            backup_data_folder
            echo ""
        fi
    fi

    local api_url download_url
    case "$tag" in
        develop)
            # Most recent release including pre-releases
            api_url="https://api.github.com/repos/$GITHUB_REPO/releases"
            download_url=$(curl -s "$api_url" \
                | grep "browser_download_url" \
                | grep -E "linux-$ARCH_SUFFIX\.tar\.gz" \
                | head -n 1 \
                | cut -d '"' -f 4)
            ;;
        latest)
            api_url="https://api.github.com/repos/$GITHUB_REPO/releases/latest"
            download_url=$(curl -s "$api_url" \
                | grep "browser_download_url" \
                | grep -E "linux-$ARCH_SUFFIX\.tar\.gz" \
                | cut -d '"' -f 4)
            ;;
        *)
            # Specific release tag. Bare version numbers like "26.4" are normalized
            # to the format used by the ErsatzTV/legacy repo (e.g. "v26.4.0").
            local resolved_tag
            resolved_tag=$(_normalize_github_tag "$tag")
            api_url="https://api.github.com/repos/$GITHUB_REPO/releases/tags/$resolved_tag"
            download_url=$(curl -s "$api_url" \
                | grep "browser_download_url" \
                | grep -E "linux-$ARCH_SUFFIX\.tar\.gz" \
                | cut -d '"' -f 4)
            ;;
    esac

    if [ -z "$download_url" ]; then
        echo "❌ Could not find a matching ErsatzTV release for tag '$tag' ($ARCH_SUFFIX)"
        echo "   Check available releases at: https://github.com/$GITHUB_REPO/releases"
        exit 1
    fi

    cd "$INSTALL_DIR"
    echo "➡️  Fetching: $download_url"
    curl -L -o ersatztv_latest.tar.gz "$download_url"
    tar -xzf ersatztv_latest.tar.gz --strip-components=1
    rm -f ersatztv_latest.tar.gz
    chown -R ersatztv:ersatztv "$INSTALL_DIR" /home/ersatztv/.local

    # Record the installed tag so future runs can display it
    echo "$tag" > "$ERSATZTV_TAG_FILE"
    chown ersatztv:ersatztv "$ERSATZTV_TAG_FILE" 2>/dev/null || true
}

detect_ersatztv_binary() {
    if [[ -x "$INSTALL_DIR/ErsatzTV" ]]; then
        echo "$INSTALL_DIR/ErsatzTV"
    elif [[ -x "$INSTALL_DIR/ErsatzTV-Legacy" ]]; then
        echo "$INSTALL_DIR/ErsatzTV-Legacy"
    else
        echo ""
    fi
}

detect_ffmpeg_path() {
    # Select the directory that contains a complete executable pair. Merely
    # finding a bin directory is insufficient because some archives/layouts
    # may leave an empty or unrelated bin directory behind.
    if [[ -x "$INSTALL_DIR/ffmpeg/bin/ffmpeg" && -x "$INSTALL_DIR/ffmpeg/bin/ffprobe" ]]; then
        echo "$INSTALL_DIR/ffmpeg/bin"
    elif [[ -x "$INSTALL_DIR/ffmpeg/ffmpeg" && -x "$INSTALL_DIR/ffmpeg/ffprobe" ]]; then
        echo "$INSTALL_DIR/ffmpeg"
    else
        echo ""
        return 1
    fi
}

find_managed_ffmpeg_binary() {
    if [[ -x "$INSTALL_DIR/ffmpeg/ffmpeg" ]]; then
        echo "$INSTALL_DIR/ffmpeg/ffmpeg"
    elif [[ -x "$INSTALL_DIR/ffmpeg/bin/ffmpeg" ]]; then
        echo "$INSTALL_DIR/ffmpeg/bin/ffmpeg"
    else
        echo ""
    fi
}

find_managed_ffprobe_binary() {
    if [[ -x "$INSTALL_DIR/ffmpeg/ffprobe" ]]; then
        echo "$INSTALL_DIR/ffmpeg/ffprobe"
    elif [[ -x "$INSTALL_DIR/ffmpeg/bin/ffprobe" ]]; then
        echo "$INSTALL_DIR/ffmpeg/bin/ffprobe"
    else
        echo ""
    fi
}

extract_binary_version() {
    local binary="$1"
    local first_line version
    first_line=$("$binary" -version 2>/dev/null | head -n 1 || true)
    version=$(printf '%s\n' "$first_line" | grep -Eo '[0-9]+(\.[0-9]+){1,2}' | head -n 1 || true)
    [[ -n "$version" ]] || return 1
    echo "$version"
}

managed_ffmpeg_is_compatible() {
    local required="$1"
    local ffmpeg_bin ffprobe_bin ffmpeg_version ffprobe_version
    ffmpeg_bin=$(find_managed_ffmpeg_binary)
    ffprobe_bin=$(find_managed_ffprobe_binary)
    [[ -n "$ffmpeg_bin" && -x "$ffmpeg_bin" ]] || return 1
    [[ -n "$ffprobe_bin" && -x "$ffprobe_bin" ]] || return 1
    ffmpeg_version=$(extract_binary_version "$ffmpeg_bin") || return 1
    ffprobe_version=$(extract_binary_version "$ffprobe_bin") || return 1
    [[ "$ffmpeg_version" == "$required" ]] || return 1
    [[ "$ffprobe_version" == "$required" ]] || return 1
    return 0
}

download_ffmpeg() {
    local ersatztv_tag="${SELECTED_TAG:-$DEFAULT_ERSATZTV_TAG}"
    local required_ffmpeg_tag current_ffmpeg_tag

    if ! _resolve_required_ffmpeg_tag "$ersatztv_tag"; then
        echo "❌ Could not determine the required FFmpeg release for ErsatzTV tag '$ersatztv_tag'."
        exit 1
    fi
    required_ffmpeg_tag="$RESOLVED_FFMPEG_VERSION"

    current_ffmpeg_tag=$(cat "$FFMPEG_TAG_FILE" 2>/dev/null || echo "")
    if [[ "$current_ffmpeg_tag" == "$required_ffmpeg_tag" ]] && managed_ffmpeg_is_compatible "$required_ffmpeg_tag"; then
        FFMPEG_PATH=$(detect_ffmpeg_path)
        echo "ℹ️  Bundled FFmpeg $current_ffmpeg_tag already matches ErsatzTV tag '$ersatztv_tag'."
        echo "$FFMPEG_PATH" > /tmp/ffmpeg_path_detected
        return 0
    elif [[ "$current_ffmpeg_tag" == "$required_ffmpeg_tag" ]]; then
        echo "⚠️  FFmpeg version marker says $required_ffmpeg_tag, but the managed ffmpeg/ffprobe files are missing, invalid, or in an unsupported layout. Reinstalling the bundle."
    fi

    if [[ -n "$current_ffmpeg_tag" ]]; then
        echo "🔹 Updating bundled FFmpeg for ErsatzTV tag '$ersatztv_tag': $current_ffmpeg_tag → $required_ffmpeg_tag"
    else
        echo "🔹 Downloading bundled FFmpeg $required_ffmpeg_tag for ErsatzTV tag '$ersatztv_tag'..."
    fi

    mkdir -p "$INSTALL_DIR/ffmpeg"
    FFMPEG_URL=$(curl -s "https://api.github.com/repos/$FFMPEG_REPO/releases/tags/$required_ffmpeg_tag" \
        | grep "browser_download_url" | grep -E "linux(64|arm64).*\.tar\.xz" | grep -i "$FFMPEG_ARCH_SUFFIX" | head -n 1 | cut -d '"' -f 4)
    if [ -z "$FFMPEG_URL" ]; then
        echo "❌ Could not find a matching FFmpeg release for tag '$required_ffmpeg_tag' ($ARCH_SUFFIX)"
        echo "   Check available releases at: https://github.com/$FFMPEG_REPO/releases"
        exit 1
    fi
    echo "➡️  Fetching: $FFMPEG_URL"
    curl -L -o ffmpeg_bundle.tar.xz "$FFMPEG_URL"
    if [ -f "ffmpeg_bundle.tar.xz" ]; then
        echo "🔹 Extracting FFmpeg..."
        tar -xf ffmpeg_bundle.tar.xz -C "$INSTALL_DIR/ffmpeg" --strip-components=1
        rm -f ffmpeg_bundle.tar.xz
        chown -R ersatztv:ersatztv "$INSTALL_DIR/ffmpeg"
        FFMPEG_PATH=$(detect_ffmpeg_path)
        echo "$required_ffmpeg_tag" > "$FFMPEG_TAG_FILE"
        if ! chown ersatztv:ersatztv "$FFMPEG_TAG_FILE" 2>/dev/null; then
            echo "⚠️  Could not update ownership for $FFMPEG_TAG_FILE; future FFmpeg upgrade checks may be affected. Re-run with sudo or check file permissions."
        fi
        echo "$FFMPEG_PATH" > /tmp/ffmpeg_path_detected
        echo "✅ FFmpeg $required_ffmpeg_tag installed to $FFMPEG_PATH"
    else
        echo "❌ FFmpeg download failed."
    fi
}

resolve_ersatztv_asset() {
    local tag="$1"
    local api_url download_url resolved_tag
    case "$tag" in
        develop)
            api_url="https://api.github.com/repos/$GITHUB_REPO/releases"
            download_url=$(curl -fsSL "$api_url" \
                | grep "browser_download_url" \
                | grep -E "linux-$ARCH_SUFFIX\.tar\.gz" \
                | head -n 1 \
                | cut -d '"' -f 4)
            ;;
        latest)
            api_url="https://api.github.com/repos/$GITHUB_REPO/releases/latest"
            download_url=$(curl -fsSL "$api_url" \
                | grep "browser_download_url" \
                | grep -E "linux-$ARCH_SUFFIX\.tar\.gz" \
                | head -n 1 \
                | cut -d '"' -f 4)
            ;;
        *)
            resolved_tag=$(_normalize_github_tag "$tag")
            api_url="https://api.github.com/repos/$GITHUB_REPO/releases/tags/$resolved_tag"
            download_url=$(curl -fsSL "$api_url" \
                | grep "browser_download_url" \
                | grep -E "linux-$ARCH_SUFFIX\.tar\.gz" \
                | head -n 1 \
                | cut -d '"' -f 4)
            ;;
    esac
    echo "$download_url"
}

resolve_ffmpeg_asset() {
    local required_ffmpeg_tag="$1"
    local release_json selected count required_no_v arch_regex api_url selected_name
    required_no_v=$(_normalize_version_tag "$required_ffmpeg_tag")
    api_url="https://api.github.com/repos/$FFMPEG_REPO/releases/tags/$required_ffmpeg_tag"

    case "$ARCH" in
        x86_64|amd64)
            # ErsatzTV FFmpeg release names have used both linux64 and linux-x64 forms.
            arch_regex='(linux64|linux[-_.]?(x64|amd64)|x86_64)'
            ;;
        aarch64|arm64)
            # Accept the current linuxarm64 form and common arm64/aarch64 variants.
            arch_regex='(linuxarm64|linux[-_.]?(arm64|aarch64)|aarch64)'
            ;;
        *)
            printf 'Unsupported FFmpeg architecture: %s\n' "$ARCH" >&2
            return 1
            ;;
    esac

    if ! release_json=$(curl -fsSL "$api_url"); then
        printf 'Unable to retrieve FFmpeg release metadata: %s\n' "$api_url" >&2
        return 1
    fi

    # A release can retain superseded builds for the same OS/architecture.
    # Filter compatible archives, then choose the newest GitHub asset by
    # uploaded_at/created_at and asset id. This selects the replacement build
    # instead of failing merely because an older build remains attached.
    selected=$(printf '%s\n' "$release_json" | jq -r \
        --arg arch_re "$arch_regex" \
        --arg ver "$required_no_v" '
            [ .assets[]?
              | select(.name and .browser_download_url)
              | select((.name | ascii_downcase) | test("\\.tar\\.xz$"))
              | select((.name | ascii_downcase) | test($arch_re; "i"))
              | select((.name | ascii_downcase) | test("(^|[-_.v]|n)" + $ver + "([-_.]|$)"; "i"))
            ]
            | sort_by(.uploaded_at // .created_at // "", .id // 0)
            | if length == 0 then empty else last | [.name, .browser_download_url] | @tsv end
        ' 2>/dev/null) || {
            printf 'Unable to parse FFmpeg release metadata for %s.\n' "$required_ffmpeg_tag" >&2
            return 1
        }

    if [[ -z "$selected" ]]; then
        printf 'No compatible FFmpeg asset found for %s on %s.\n' \
            "$required_ffmpeg_tag" "$ARCH" >&2
        printf 'Available release assets:\n' >&2
        printf '%s\n' "$release_json" | jq -r '.assets[]?.name // empty' | sed 's/^/  - /' >&2
        return 1
    fi

    IFS=$'\t' read -r selected_name RESOLVED_FFMPEG_ASSET_URL count <<< "$selected"

    # The jq expression above reports the selected object rather than the
    # candidate-array length, so calculate the count separately for diagnostics.
    count=$(printf '%s\n' "$release_json" | jq -r \
        --arg arch_re "$arch_regex" \
        --arg ver "$required_no_v" '
            [ .assets[]?
              | select(.name and .browser_download_url)
              | select((.name | ascii_downcase) | test("\\.tar\\.xz$"))
              | select((.name | ascii_downcase) | test($arch_re; "i"))
              | select((.name | ascii_downcase) | test("(^|[-_.v]|n)" + $ver + "([-_.]|$)"; "i"))
            ] | length
        ')

    if [[ "$count" -gt 1 ]]; then
        printf 'ℹ️  Found %s compatible FFmpeg assets; selecting newest: %s\n' \
            "$count" "$selected_name" >&2
    else
        printf 'ℹ️  Selected FFmpeg asset: %s\n' "$selected_name" >&2
    fi

    printf '%s\n' "$RESOLVED_FFMPEG_ASSET_URL"
}

create_staging_directory() {
    STAGING_DIR=$(mktemp -d /tmp/ersatztv-stage-XXXXXX)
    mkdir -p "$STAGING_DIR/app" "$STAGING_DIR/ffmpeg"
    echo "🧪 Staging directory: $STAGING_DIR"
}

verify_download() {
    local file_path="$1"
    local minimum_bytes="$2"
    local actual_bytes
    [[ -f "$file_path" ]] || return 1
    actual_bytes=$(wc -c < "$file_path")
    [[ "$actual_bytes" -ge "$minimum_bytes" ]]
}

download_file() {
    local url="$1"
    local output="$2"
    local min_bytes="${3:-4096}"
    curl -fL --retry 2 --retry-delay 1 -o "$output" "$url"
    if ! verify_download "$output" "$min_bytes"; then
        log_error "Downloaded file is missing or unexpectedly small: $output"
        return 1
    fi
}

extract_archive() {
    local archive_path="$1"
    local destination="$2"
    local strip_components="$3"
    mkdir -p "$destination"
    case "$archive_path" in
        *.tar.gz) tar -xzf "$archive_path" -C "$destination" --strip-components="$strip_components" ;;
        *.tar.xz) tar -xf "$archive_path" -C "$destination" --strip-components="$strip_components" ;;
        *)
            log_error "Unsupported archive type: $archive_path"
            return 1
            ;;
    esac
}

validate_staged_ersatztv() {
    local staged_binary=""
    if [[ -x "$STAGING_DIR/app/ErsatzTV" ]]; then
        staged_binary="$STAGING_DIR/app/ErsatzTV"
    elif [[ -x "$STAGING_DIR/app/ErsatzTV-Legacy" ]]; then
        staged_binary="$STAGING_DIR/app/ErsatzTV-Legacy"
    fi
    if [[ -z "$staged_binary" ]]; then
        log_error "No executable staged ErsatzTV binary found."
        return 1
    fi
    echo "$staged_binary"
}

validate_staged_ffmpeg() {
    local required="$1"
    local staged_ffmpeg="" staged_ffprobe="" ffmpeg_version ffprobe_version
    if [[ -x "$STAGING_DIR/ffmpeg/ffmpeg" ]]; then
        staged_ffmpeg="$STAGING_DIR/ffmpeg/ffmpeg"
        staged_ffprobe="$STAGING_DIR/ffmpeg/ffprobe"
    elif [[ -x "$STAGING_DIR/ffmpeg/bin/ffmpeg" ]]; then
        staged_ffmpeg="$STAGING_DIR/ffmpeg/bin/ffmpeg"
        staged_ffprobe="$STAGING_DIR/ffmpeg/bin/ffprobe"
    fi
    if [[ -z "$staged_ffmpeg" || ! -x "$staged_ffprobe" ]]; then
        log_error "No valid staged FFmpeg/FFprobe executable pair found."
        return 1
    fi
    ffmpeg_version=$(extract_binary_version "$staged_ffmpeg") || return 1
    ffprobe_version=$(extract_binary_version "$staged_ffprobe") || return 1
    if [[ "$ffmpeg_version" != "$required" || "$ffprobe_version" != "$required" ]]; then
        log_error "Staged FFmpeg bundle version mismatch. Required: $required, ffmpeg: $ffmpeg_version, ffprobe: $ffprobe_version."
        return 1
    fi
    echo "$staged_ffmpeg"
}

capture_service_state() {
    SERVICE_UNIT_EXISTS=false
    SERVICE_WAS_ENABLED=false
    SERVICE_WAS_ACTIVE=false
    ORIGINAL_RESTART_POLICY=""

    if systemctl list-unit-files "${SERVICE_NAME}.service" >/dev/null 2>&1; then
        SERVICE_UNIT_EXISTS=true
    fi
    if systemctl is-enabled "$SERVICE_NAME" >/dev/null 2>&1; then
        SERVICE_WAS_ENABLED=true
    fi
    if systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1; then
        SERVICE_WAS_ACTIVE=true
    fi
    ORIGINAL_RESTART_POLICY=$(systemctl show "$SERVICE_NAME" -p Restart --value 2>/dev/null || true)
}

disable_service_restart() {
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
    if [[ -f "$service_file" ]]; then
        sed -i 's/^Restart=.*/Restart=no/' "$service_file" 2>/dev/null || true
        systemctl daemon-reload 2>/dev/null || true
    fi
}

restore_service_policy() {
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
    if [[ -n "$ORIGINAL_RESTART_POLICY" && -f "$service_file" ]]; then
        sed -i "s/^Restart=.*/Restart=$ORIGINAL_RESTART_POLICY/" "$service_file" 2>/dev/null || true
        systemctl daemon-reload 2>/dev/null || true
    fi
}

create_transaction_backup() {
    TRANSACTION_BACKUP_DIR=$(mktemp -d /opt/ersatztv-tx-backup-XXXXXX)
    mkdir -p "$TRANSACTION_BACKUP_DIR"
    if [[ -d "$INSTALL_DIR" ]]; then
        cp -a "$INSTALL_DIR" "$TRANSACTION_BACKUP_DIR/install_dir"
    fi
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        cp -a "/etc/systemd/system/${SERVICE_NAME}.service" "$TRANSACTION_BACKUP_DIR/${SERVICE_NAME}.service"
    fi
}

install_ersatztv_files() {
    local replace_managed_ffmpeg="${1:-true}"
    local preserved_ffmpeg=""

    # Official Linux upgrade guidance requires the application directory to
    # be emptied before extracting the new release. Preserve the separately
    # managed FFmpeg bundle only when it has already been validated and does
    # not need replacement.
    if [[ "$replace_managed_ffmpeg" != true && -d "$INSTALL_DIR/ffmpeg" ]]; then
        preserved_ffmpeg="$STAGING_DIR/preserved-managed-ffmpeg"
        mv "$INSTALL_DIR/ffmpeg" "$preserved_ffmpeg"
    fi

    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    cp -a "$STAGING_DIR/app/." "$INSTALL_DIR/"

    if [[ -n "$preserved_ffmpeg" ]]; then
        # Never let an application archive's bundled/placeholder ffmpeg path
        # override the previously validated managed bundle.
        rm -rf "$INSTALL_DIR/ffmpeg"
        mv "$preserved_ffmpeg" "$INSTALL_DIR/ffmpeg"
    fi
}

install_ffmpeg_files() {
    rm -rf "$INSTALL_DIR/ffmpeg"
    mkdir -p "$INSTALL_DIR/ffmpeg"
    cp -a "$STAGING_DIR/ffmpeg/." "$INSTALL_DIR/ffmpeg/"
}

apply_ownership() {
    chown -R ersatztv:ersatztv "$INSTALL_DIR" /home/ersatztv/.local
}

apply_permissions() {
    chmod 755 "$INSTALL_DIR" 2>/dev/null || true
    chmod 700 "$DATA_FOLDER" 2>/dev/null || true
}

apply_selinux_contexts() {
    if [[ "$SELINUX_ENFORCING" == true ]]; then
        chcon -R -t bin_t /opt/ersatztv 2>/dev/null || true
        chcon -R -t home_root_t /home/ersatztv 2>/dev/null || true
    fi
}

rollback_transaction() {
    log_warn "Transaction failed. Attempting rollback..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    if [[ -d "$TRANSACTION_BACKUP_DIR/install_dir" ]]; then
        rm -rf "$INSTALL_DIR"
        cp -a "$TRANSACTION_BACKUP_DIR/install_dir" "$INSTALL_DIR"
    fi
    if [[ -f "$TRANSACTION_BACKUP_DIR/${SERVICE_NAME}.service" ]]; then
        cp -a "$TRANSACTION_BACKUP_DIR/${SERVICE_NAME}.service" "/etc/systemd/system/${SERVICE_NAME}.service"
        systemctl daemon-reload 2>/dev/null || true
    fi
    apply_ownership
    apply_permissions
    apply_selinux_contexts
    restore_service_policy
    if [[ "$SERVICE_WAS_ENABLED" == true ]]; then
        systemctl enable "$SERVICE_NAME" 2>/dev/null || true
    else
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    fi
    if [[ "$SERVICE_WAS_ACTIVE" == true ]]; then
        systemctl start "$SERVICE_NAME" 2>/dev/null || true
    fi
}

cleanup_transaction() {
    [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]] && rm -rf "$STAGING_DIR"
}

create_service() {
    echo "🔹 Creating systemd service..."
    FFMPEG_PATH=$(cat /tmp/ffmpeg_path_detected 2>/dev/null || echo "$INSTALL_DIR/ffmpeg")

    DETECTED_BINARY=$(detect_ersatztv_binary)
    if [[ -z "$DETECTED_BINARY" ]]; then
        echo "❌ Cannot find ErsatzTV binary in $INSTALL_DIR (tried ErsatzTV, ErsatzTV-Legacy)."
        exit 1
    fi
    echo "✅ Detected binary: $DETECTED_BINARY"

    cat <<EOF > /etc/systemd/system/${SERVICE_NAME}.service
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
Environment=HOME=/home/ersatztv
Environment=PATH=$FFMPEG_PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

    if [[ "$SELINUX_ENFORCING" == true ]]; then
        echo "🔹 Adjusting SELinux contexts for /opt/ersatztv and /home/ersatztv..."
        chcon -R -t bin_t /opt/ersatztv 2>/dev/null || true
        chcon -R -t home_root_t /home/ersatztv 2>/dev/null || true
    fi

    rm -f /tmp/ffmpeg_path_detected
}

configure_firewall() {
    echo "🔹 Checking firewall status and allowing port 8409..."

    # --- Fedora / RHEL / firewalld ------------------------------------------
    if command -v firewall-cmd >/dev/null 2>&1; then
        if systemctl is-active --quiet firewalld; then
            echo "   Detected firewalld; opening port 8409/tcp..."
            firewall-cmd --permanent --add-port=8409/tcp >/dev/null 2>&1 || true
            firewall-cmd --reload >/dev/null 2>&1 || true
            echo "   ✅ Port 8409 opened in firewalld."
        else
            echo "   ℹ️  firewalld not active — skipping."
        fi

    # --- Debian / Ubuntu / ufw ----------------------------------------------
    elif command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            echo "   Detected ufw; allowing port 8409/tcp..."
            ufw allow 8409/tcp >/dev/null 2>&1 || true
            echo "   ✅ Port 8409 opened in ufw."
        else
            echo "   ℹ️  ufw is installed but not active — skipping."
        fi

    else
        echo "   ⚙️  No known firewall manager detected (firewalld/ufw)."
    fi

    # Display common accessible IP so users know where to connect
    HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -n "$HOST_IP" ]; then
        echo "🌐 ErsatzTV web interface: http://$HOST_IP:8409"
    else
        echo "🌐 ErsatzTV web interface: http://<server-ip>:8409"
    fi
}

install_updater() {
    echo "🔹 Installing compatibility updater wrapper..."
    cat <<'EOS' > "$UPDATER_PATH"
#!/bin/bash
set -euo pipefail
echo "Warning: command \"update_linux_ersatztv.sh\" is deprecated." >&2
echo "Use \"ersatztv-linux-automation --upgrade\" instead." >&2
exec /usr/local/sbin/ersatztv-linux-automation --upgrade "$@"
EOS
    chmod +x "$UPDATER_PATH"
    echo "✅ Compatibility updater installed at $UPDATER_PATH"
}

install_management_command() {
    local source_script tmp_file downloaded_source=""

    source_script=$(readlink -f "$0" 2>/dev/null || true)
    if [[ -z "$source_script" || ! -r "$source_script" ]]; then
        downloaded_source=$(mktemp /tmp/ersatztv-linux-automation-source.XXXXXX)
        if curl -fsSL "$RAW_SCRIPT_URL" -o "$downloaded_source"; then
            source_script="$downloaded_source"
        else
            rm -f "$downloaded_source"
            log_warn "Could not locate local script source and failed to download $RAW_SCRIPT_URL."
            return 1
        fi
    fi

    mkdir -p "$(dirname "$AUTOMATION_CMD_PATH")"
    tmp_file=$(mktemp "$(dirname "$AUTOMATION_CMD_PATH")/.ersatztv-linux-automation.XXXXXX")
    cp "$source_script" "$tmp_file"
    chown root:root "$tmp_file"
    chmod 0755 "$tmp_file"
    mv -f "$tmp_file" "$AUTOMATION_CMD_PATH"
    rm -f "$downloaded_source"
    rm -f "$LEGACY_AUTOMATION_CMD_PATH"
    echo "✅ Management command installed at $AUTOMATION_CMD_PATH"
}

install_compatibility_commands() {
    cat <<'EOS' > "$INSTALLER_COMPAT_PATH"
#!/bin/bash
set -euo pipefail
echo "Warning: command \"install_linux_ersatztv.sh\" is deprecated." >&2
echo "Use \"ersatztv-linux-automation --install\" instead." >&2
exec /usr/local/sbin/ersatztv-linux-automation --install "$@"
EOS
    chmod 0755 "$INSTALLER_COMPAT_PATH"
    install_updater
    echo "✅ Compatibility installer installed at $INSTALLER_COMPAT_PATH"
}

install_retroiptvguide() {
    echo "🔹 Installing RetroIPTVGuide..."
    cd /opt

    # Download latest testing branch unified installer
    RETRO_SCRIPT_URL="https://raw.githubusercontent.com/thehack904/RetroIPTVGuide/refs/heads/testing/retroiptv_linux.sh"
    RETRO_SCRIPT_PATH="/opt/retroiptv_linux.sh"

    echo "➡️  Fetching RetroIPTVGuide unified installer..."
    curl -fsSL "$RETRO_SCRIPT_URL" -o "$RETRO_SCRIPT_PATH"
    chmod +x "$RETRO_SCRIPT_PATH"

    echo "🧩 Launching RetroIPTVGuide installer..."
    if [[ $EUID -eq 0 ]]; then
        bash -c "bash $RETRO_SCRIPT_PATH install < /dev/tty"
    else
        sudo bash -c "bash $RETRO_SCRIPT_PATH install < /dev/tty"
    fi

    echo "✅ RetroIPTVGuide installation complete."
}

uninstall_retroiptvguide() {
    echo "🔹 Uninstalling RetroIPTVGuide..."
    RETRO_SCRIPT_PATH="/opt/retroiptv_linux.sh"

    # If the unified installer already exists, reuse it
    if [[ -f "$RETRO_SCRIPT_PATH" ]]; then
        echo "➡️  Running built-in uninstaller..."
        if [[ $EUID -eq 0 ]]; then
            bash -c "bash $RETRO_SCRIPT_PATH uninstall < /dev/tty"
        else
            sudo bash -c "bash $RETRO_SCRIPT_PATH uninstall < /dev/tty"
        fi
    elif [[ -d "/home/iptv/iptv-server" && -f "/home/iptv/iptv-server/uninstall.sh" ]]; then
        echo "➡️  Fallback: Running legacy uninstaller..."
        sudo -u iptv bash -H -c "cd /home/iptv/iptv-server && sudo bash uninstall.sh"
    else
        echo "⚠️  No RetroIPTVGuide uninstaller found."
    fi

    echo "✅ RetroIPTVGuide uninstallation complete."
}

remove_firewall_rule() {
    echo "🔹 Checking firewall to remove port 8409..."

    # --- Fedora / RHEL / firewalld ------------------------------------------
    if command -v firewall-cmd >/dev/null 2>&1; then
        if systemctl is-active --quiet firewalld; then
            echo "   Detected firewalld; removing port 8409/tcp..."
            firewall-cmd --permanent --remove-port=8409/tcp >/dev/null 2>&1 || true
            firewall-cmd --reload >/dev/null 2>&1 || true
            echo "   ✅ Port 8409 removed from firewalld."
        else
            echo "   ℹ️  firewalld not active — skipping."
        fi

    # --- Debian / Ubuntu / ufw ----------------------------------------------
    elif command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            echo "   Detected ufw; removing port 8409/tcp..."
            ufw delete allow 8409/tcp >/dev/null 2>&1 || true
            echo "   ✅ Port 8409 removed from ufw."
        else
            echo "   ℹ️  ufw installed but not active — skipping."
        fi

    else
        echo "   ⚙️  No known firewall manager detected (firewalld/ufw)."
    fi
}

preflight_check() {
    local binary="$1"
    local preflight_errors=0

    echo "🔍 Running preflight validation..."

    # 1. Install directory must exist
    if [[ ! -d "$INSTALL_DIR" ]]; then
        echo "❌ Install directory $INSTALL_DIR does not exist."
        (( preflight_errors++ ))
    else
        echo "✅ Install directory $INSTALL_DIR exists."
    fi

    # 2. Expected executable must exist
    if [[ ! -e "$binary" ]]; then
        echo "❌ Expected executable $binary does not exist."
        (( preflight_errors++ ))
    else
        echo "✅ Executable $binary exists."
    fi

    # 3. Expected executable must have execute permission
    if [[ ! -x "$binary" ]]; then
        echo "❌ Executable $binary does not have execute permission."
        (( preflight_errors++ ))
    else
        echo "✅ Executable $binary has execute permission."
    fi

    # 4. Data folder must exist
    if [[ ! -d "$DATA_FOLDER" ]]; then
        echo "❌ Data folder $DATA_FOLDER does not exist."
        (( preflight_errors++ ))
    else
        echo "✅ Data folder $DATA_FOLDER exists."
    fi

    # 5. Service unit must reference the installed executable
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
    if [[ -f "$service_file" ]]; then
        local service_exec
        service_exec=$(grep -E '^ExecStart=' "$service_file" | sed 's/^ExecStart=//' | awk '{print $1}')
        if [[ "$service_exec" != "$binary" ]]; then
            echo "❌ Service unit ExecStart ($service_exec) does not match installed binary ($binary)."
            (( preflight_errors++ ))
        else
            echo "✅ Service unit references the installed binary."
        fi
    else
        echo "⚠️  Service unit $service_file not found (skipping ExecStart check)."
    fi

    # 6. ersatztv user must own the install directory and data folder
    if [[ -d "$INSTALL_DIR" ]]; then
        local install_owner
        install_owner=$(stat -c '%U' "$INSTALL_DIR")
        if [[ "$install_owner" != "ersatztv" ]]; then
            echo "❌ $INSTALL_DIR is owned by '$install_owner', expected 'ersatztv'."
            (( preflight_errors++ ))
        else
            echo "✅ $INSTALL_DIR is owned by ersatztv."
        fi
    fi

    if [[ -d "$DATA_FOLDER" ]]; then
        local data_owner
        data_owner=$(stat -c '%U' "$DATA_FOLDER")
        if [[ "$data_owner" != "ersatztv" ]]; then
            echo "❌ $DATA_FOLDER is owned by '$data_owner', expected 'ersatztv'."
            (( preflight_errors++ ))
        else
            echo "✅ $DATA_FOLDER is owned by ersatztv."
        fi
    fi

    if [[ "$preflight_errors" -gt 0 ]]; then
        echo "❌ Preflight validation failed with $preflight_errors error(s). Service restart aborted."
        exit 1
    fi

    echo "✅ All preflight checks passed."
}

verify_startup() {
    echo "🔹 Verifying ErsatzTV startup..."
    for i in {1..20}; do
        if curl -fs http://127.0.0.1:8409 >/dev/null 2>&1; then
            echo "✅ ErsatzTV web interface is responding on port 8409."
            return
        fi
        sleep 2
    done
    echo "⚠️ ErsatzTV did not respond within 40 seconds."
    if [ ! -d "$DATA_FOLDER/logs" ]; then
        echo "ℹ️ No logs directory yet — ErsatzTV may not have started."
        echo "   Check service status with: sudo systemctl status ersatztv"
    fi
}

verify_ersatztv_ffmpeg_health() {
    local managed_dir expected_ffmpeg expected_ffprobe detected_ffmpeg detected_ffprobe latest_log

    FFMPEG_HEALTH_WARNING=false
    FFMPEG_HEALTH_DETAIL=""

    if ! managed_dir=$(detect_ffmpeg_path); then
        FFMPEG_HEALTH_WARNING=true
        FFMPEG_HEALTH_DETAIL="The managed FFmpeg executable directory could not be detected."
        log_warn "$FFMPEG_HEALTH_DETAIL"
        return 1
    fi

    expected_ffmpeg="$managed_dir/ffmpeg"
    expected_ffprobe="$managed_dir/ffprobe"

    # ErsatzTV records the resolved executable paths at startup. Prefer the
    # application log because not every installation forwards these lines to journald.
    latest_log=$(find "$DATA_FOLDER/logs" -maxdepth 1 -type f -name 'ersatztv*.log' -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr | head -1 | cut -d' ' -f2-)
    if [[ -n "$latest_log" && -r "$latest_log" ]]; then
        detected_ffmpeg=$(tail -n 500 "$latest_log" | sed -n 's/.*Located ffmpeg at //p' | tail -1)
        detected_ffprobe=$(tail -n 500 "$latest_log" | sed -n 's/.*Located ffprobe at //p' | tail -1)
    fi

    if [[ -z "$detected_ffmpeg" ]]; then
        detected_ffmpeg=$(journalctl -u "$SERVICE_NAME" --no-pager -n 500 2>/dev/null \
            | sed -n 's/.*Located ffmpeg at //p' | tail -1)
    fi
    if [[ -z "$detected_ffprobe" ]]; then
        detected_ffprobe=$(journalctl -u "$SERVICE_NAME" --no-pager -n 500 2>/dev/null \
            | sed -n 's/.*Located ffprobe at //p' | tail -1)
    fi

    if [[ "$detected_ffmpeg" == "$expected_ffmpeg" && "$detected_ffprobe" == "$expected_ffprobe" ]]; then
        echo "✅ ErsatzTV is using the managed FFmpeg and FFprobe executables."
        return 0
    fi

    FFMPEG_HEALTH_WARNING=true
    if [[ -n "$detected_ffmpeg" || -n "$detected_ffprobe" ]]; then
        FFMPEG_HEALTH_DETAIL="ErsatzTV resolved FFmpeg='${detected_ffmpeg:-unknown}' and FFprobe='${detected_ffprobe:-unknown}' instead of the managed executables."
    else
        FFMPEG_HEALTH_DETAIL="The installer could not confirm which FFmpeg and FFprobe executables ErsatzTV selected."
    fi
    log_warn "$FFMPEG_HEALTH_DETAIL"
    return 1
}

perform_install_or_upgrade() {
    local ersatztv_tag="${SELECTED_TAG:-$DEFAULT_ERSATZTV_TAG}"
    local required_ffmpeg_tag ersatztv_asset_url ffmpeg_asset_url
    local staged_binary staged_ffmpeg_binary
    local replace_ffmpeg=true installed_ffmpeg_version version_cmp

    # Discovery
    if ! _resolve_required_ffmpeg_tag "$ersatztv_tag"; then
        log_error "Unable to determine the managed FFmpeg requirement for ErsatzTV tag '$ersatztv_tag'. No changes were made."
        exit 1
    fi
    required_ffmpeg_tag="$RESOLVED_FFMPEG_VERSION"
    echo "Selected ErsatzTV release: $RESOLVED_ERSATZTV_TAG"
    echo "Resolved managed FFmpeg:   $required_ffmpeg_tag"
    echo "Requirement source:        $RESOLVED_FFMPEG_SOURCE"
    echo "Requirement confidence:    $RESOLVED_FFMPEG_CONFIDENCE"

    if managed_ffmpeg_is_compatible "$required_ffmpeg_tag"; then
        replace_ffmpeg=false
        log_info "Managed FFmpeg already matches required version $required_ffmpeg_tag."
    else
        installed_ffmpeg_version=$(extract_binary_version "$(find_managed_ffmpeg_binary)" 2>/dev/null || echo "")
        if [[ -n "$installed_ffmpeg_version" ]]; then
            version_cmp=$(_version_compare "$installed_ffmpeg_version" "$required_ffmpeg_tag")
            if [[ "$version_cmp" == "1" ]]; then
                log_warn "Installed managed FFmpeg ($installed_ffmpeg_version) is newer than required ($required_ffmpeg_tag) but not explicitly verified. Replacing with required version."
            else
                log_info "Managed FFmpeg replacement required. Installed: $installed_ffmpeg_version, required: $required_ffmpeg_tag."
            fi
        else
            log_info "Managed FFmpeg replacement required because managed FFmpeg/FFprobe is missing, invalid, or not executable."
        fi
    fi

    if ! ersatztv_asset_url=$(resolve_ersatztv_asset "$ersatztv_tag"); then
        log_error "Could not resolve an ErsatzTV asset for tag '$ersatztv_tag' and architecture '$ARCH_SUFFIX'."
        exit 1
    fi
    if [[ -z "$ersatztv_asset_url" ]]; then
        log_error "The ErsatzTV asset resolver returned an empty URL for tag '$ersatztv_tag' and architecture '$ARCH_SUFFIX'."
        exit 1
    fi
    if [[ "$replace_ffmpeg" == true ]]; then
        if ! ffmpeg_asset_url=$(resolve_ffmpeg_asset "$required_ffmpeg_tag"); then
            log_error "Could not resolve an FFmpeg asset from $FFMPEG_REPO release '$required_ffmpeg_tag' for architecture '$ARCH'."
            exit 1
        fi
        if [[ -z "$ffmpeg_asset_url" ]]; then
            log_error "The FFmpeg asset resolver returned an empty URL for release '$required_ffmpeg_tag' and architecture '$ARCH'."
            exit 1
        fi
    fi

    # Staging (before any live-file modification)
    create_staging_directory
    echo "➡️  Fetching staged app asset: $ersatztv_asset_url"
    download_file "$ersatztv_asset_url" "$STAGING_DIR/ersatztv.tar.gz" 10240
    extract_archive "$STAGING_DIR/ersatztv.tar.gz" "$STAGING_DIR/app" 1
    staged_binary=$(validate_staged_ersatztv)

    if [[ "$replace_ffmpeg" == true ]]; then
        echo "➡️  Fetching staged FFmpeg asset: $ffmpeg_asset_url"
        download_file "$ffmpeg_asset_url" "$STAGING_DIR/ffmpeg.tar.xz" 10240
        extract_archive "$STAGING_DIR/ffmpeg.tar.xz" "$STAGING_DIR/ffmpeg" 1
        staged_ffmpeg_binary=$(validate_staged_ffmpeg "$required_ffmpeg_tag")
    fi

    # Backup + service state
    capture_service_state
    if [[ "$SERVICE_UNIT_EXISTS" == true ]]; then
        disable_service_restart
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    fi
    create_transaction_backup

    # Installation + validation with rollback guard
    set +e
    install_ersatztv_files "$replace_ffmpeg"
    if [[ "$replace_ffmpeg" == true ]]; then
        install_ffmpeg_files
    fi
    if ! FFMPEG_PATH=$(detect_ffmpeg_path); then
        log_error "Managed FFmpeg layout is invalid after installation; ffmpeg and ffprobe were not found together in a supported directory."
        rollback_transaction
        cleanup_transaction
        set -e
        exit 1
    fi
    echo "$FFMPEG_PATH" > /tmp/ffmpeg_path_detected
    create_service
    apply_ownership
    apply_permissions
    apply_selinux_contexts
    echo "$ersatztv_tag" > "$ERSATZTV_TAG_FILE"
    echo "$required_ffmpeg_tag" > "$FFMPEG_TAG_FILE"
    chown ersatztv:ersatztv "$ERSATZTV_TAG_FILE" "$FFMPEG_TAG_FILE" 2>/dev/null || true
    install_management_command
    install_compatibility_commands
    preflight_check "$(detect_ersatztv_binary)"
    systemctl daemon-reload
    if [[ "$SERVICE_WAS_ENABLED" == true || "$ACTION" == "install" ]]; then
        systemctl enable "$SERVICE_NAME" 2>/dev/null || true
    fi
    if [[ "$ACTION" == "install" || "$SERVICE_WAS_ACTIVE" == true ]]; then
        systemctl restart "$SERVICE_NAME"
        verify_startup
        verify_ersatztv_ffmpeg_health || true
    fi
    if ! managed_ffmpeg_is_compatible "$required_ffmpeg_tag"; then
        rollback_transaction
        cleanup_transaction
        set -e
        exit 1
    fi
    _write_cached_ffmpeg_requirement
    set -e

    restore_service_policy
    cleanup_transaction
}

perform_repair() {
    local detected_binary service_file
    local installed_tag required_ffmpeg_tag ffmpeg_asset_url
    service_file="/etc/systemd/system/${SERVICE_NAME}.service"
    capture_service_state
    detected_binary=$(detect_ersatztv_binary)
    if [[ -z "$detected_binary" ]]; then
        log_error "No managed ErsatzTV binary found at $INSTALL_DIR."
        exit 1
    fi
    chmod +x "$detected_binary" 2>/dev/null || true

    installed_tag=$(cat "$ERSATZTV_TAG_FILE" 2>/dev/null || cat "$INSTALL_DIR/.installed_tag" 2>/dev/null || echo "")
    if [[ -z "$installed_tag" ]]; then
        log_error "Repair could not determine the installed ErsatzTV release tag."
        exit 1
    fi
    if ! _resolve_required_ffmpeg_tag "$installed_tag"; then
        log_error "Repair could not resolve required managed FFmpeg for installed tag '$installed_tag'."
        exit 1
    fi
    required_ffmpeg_tag="$RESOLVED_FFMPEG_VERSION"
    if ! managed_ffmpeg_is_compatible "$required_ffmpeg_tag"; then
        ffmpeg_asset_url=$(resolve_ffmpeg_asset "$required_ffmpeg_tag")
        if [[ -z "$ffmpeg_asset_url" ]]; then
            log_error "Repair could not resolve FFmpeg asset for required version '$required_ffmpeg_tag'."
            exit 1
        fi
        create_staging_directory
        echo "➡️  Repair staging FFmpeg asset: $ffmpeg_asset_url"
        download_file "$ffmpeg_asset_url" "$STAGING_DIR/ffmpeg.tar.xz" 10240
        extract_archive "$STAGING_DIR/ffmpeg.tar.xz" "$STAGING_DIR/ffmpeg" 1
        validate_staged_ffmpeg "$required_ffmpeg_tag" >/dev/null
        if [[ "$SERVICE_WAS_ACTIVE" == true ]]; then
            systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        fi
        install_ffmpeg_files
        echo "$required_ffmpeg_tag" > "$FFMPEG_TAG_FILE"
        echo "$(detect_ffmpeg_path)" > /tmp/ffmpeg_path_detected
        cleanup_transaction
    fi

    apply_ownership
    apply_permissions
    apply_selinux_contexts

    if [[ -f "$service_file" ]]; then
        sed -i "s|^ExecStart=.*|ExecStart=$detected_binary --data-folder $DATA_FOLDER|" "$service_file"
        if ! grep -q '^Restart=' "$service_file"; then
            echo "Restart=on-failure" >> "$service_file"
        else
            sed -i 's/^Restart=.*/Restart=on-failure/' "$service_file"
        fi
    else
        create_service
    fi
    install_management_command
    install_compatibility_commands
    preflight_check "$detected_binary"
    systemctl daemon-reload 2>/dev/null || true
    if [[ "$SERVICE_WAS_ENABLED" == true ]]; then
        systemctl enable "$SERVICE_NAME" 2>/dev/null || true
    fi
    if [[ "$SERVICE_WAS_ACTIVE" == true ]]; then
        systemctl restart "$SERVICE_NAME" 2>/dev/null || true
    fi
    _write_cached_ffmpeg_requirement
}

uninstall_ersatztv() {
    local purge_flag="$1"
    local confirm

    echo "🔹 Stopping and disabling ErsatzTV service..."
    systemctl stop $SERVICE_NAME 2>/dev/null || true
    systemctl disable $SERVICE_NAME 2>/dev/null || true
    rm -f /etc/systemd/system/${SERVICE_NAME}.service
    systemctl daemon-reload

    echo "🔹 Removing ErsatzTV application files..."
    rm -rf "$INSTALL_DIR" "$UPDATER_PATH" "$INSTALLER_COMPAT_PATH" "$AUTOMATION_CMD_PATH" "$LEGACY_AUTOMATION_CMD_PATH"
    echo
    echo "🧩 ErsatzTV data is stored in: $DATA_FOLDER"
    echo "This folder contains all configuration, databases, logs, and secrets."
    echo

    if [[ "$purge_flag" == "--purge" ]]; then
        echo "⚠️ Purge mode enabled."
        echo "⚠️ This will permanently delete: /home/ersatztv"
        if [ -t 0 ]; then
            read -rp "Type PURGE to permanently remove user data: " confirm || true
            if [[ "$confirm" != "PURGE" ]]; then
                log_warn "Purge not confirmed. User data was preserved."
            else
                userdel -r ersatztv 2>/dev/null || true
                echo "✅ ersatztv user and all data removed."
            fi
        else
            log_error "--purge requires interactive confirmation in the current release."
            exit 1
        fi
    elif [ -t 0 ]; then
        # Interactive terminal, safe to prompt
        read -rp "Do you also want to remove the 'ersatztv' user and its home directory? (y/N): " confirm || true
        confirm=${confirm,,}
        if [[ "$confirm" == "y" || "$confirm" == "yes" ]]; then
            echo "⚠️ Removing ersatztv user and all associated data..."
            userdel -r ersatztv 2>/dev/null || true
            echo "✅ ersatztv user and home directory removed."
        else
            echo "ℹ️ Keeping ersatztv user and home directory at /home/ersatztv"
        fi
    else
        # Non-interactive (piped curl/bash)
        echo "ℹ️ Non-interactive mode detected — keeping ersatztv user and home directory."
    fi

    remove_firewall_rule

    echo "✅ ErsatzTV has been uninstalled."
}

show_final_summary() {
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')

    echo ""
    echo "============================================================"
    echo " ✅ Installation Complete!"
    echo "============================================================"
    echo ""
    echo "🌐 ErsatzTV Legacy web interface: http://${server_ip}:8409"
    if [[ "$1" == "retro" ]]; then
        echo "🌐 RetroIPTVGuide web interface: http://${server_ip}:5000"
        echo "       - Default login: admin / strongpassword123"
        echo "       NOTE: This is a **BETA build**."
        echo "       Do NOT expose RetroIPTVGuide directly to the public internet."
    fi
    echo ""
    echo "🧩 Services installed:"
    echo "   • ersatztv.service  → manages ErsatzTV"
    if [[ "$1" == "retro" ]]; then
        echo "   • iptv-server.service → manages RetroIPTVGuide"
    fi
    echo ""
    if [[ "$FFMPEG_HEALTH_WARNING" == true ]]; then
        echo "⚠️  FFmpeg health check needs attention:"
        echo "   $FFMPEG_HEALTH_DETAIL"
        echo ""
        echo "   In ErsatzTV, open Settings and verify:"
        echo "   FFmpeg Path:  /opt/ersatztv/ffmpeg/bin/ffmpeg"
        echo "   FFprobe Path: /opt/ersatztv/ffmpeg/bin/ffprobe"
        echo ""
        echo "   Save the settings, then restart ErsatzTV:"
        echo "   sudo systemctl restart ersatztv"
        echo ""
    fi
    echo "Use the following to manage services:"
    echo "   sudo systemctl status ersatztv"
    if [[ "$1" == "retro" ]]; then
        echo "   sudo systemctl status iptv-server"
    fi
    echo ""
    echo "============================================================"
}

# --- Main Execution ----------------------------------------------------------
parse_arguments "$@"
validate_arguments

if [[ "$ACTION" == "help" ]]; then
    show_usage 0
fi

if [[ "$ACTION" == "version" ]]; then
    print_version
    exit 0
fi

echo "ErsatzTV Linux Automation $AUTOMATION_VERSION"
echo "Target: ErsatzTV Legacy only — ErsatzTV Next is not supported."

validate_supported_architecture
check_root
acquire_lock
trap release_lock EXIT

case "$ACTION" in
    install|upgrade)
        check_existing_version
        if [[ "$ACTION" == "install" ]] && has_managed_installation; then
            log_error "An existing installation was detected. Use --upgrade, --repair, or --uninstall."
            exit 1
        fi
        if [[ "$ACTION" == "upgrade" ]] && ! has_managed_installation; then
            log_error "No existing managed installation found. Use --install first."
            exit 1
        fi
        select_ersatztv_version
        create_user_and_dirs
        perform_install_or_upgrade

        if [[ "$RETROIPTVGUIDE_FLAG" == true ]]; then
            install_retroiptvguide
            show_final_summary "retro"
        else
            show_final_summary
        fi
        ;;
    repair)
        if ! has_managed_installation; then
            log_error "No existing managed installation found. Repair requires an installed system."
            exit 1
        fi
        create_user_and_dirs
        perform_repair
        ;;
    uninstall)
        if [[ "$PURGE_FLAG" == true ]]; then
            uninstall_ersatztv "--purge" ""
        else
            uninstall_ersatztv "" ""
        fi
        if [[ "$RETROIPTVGUIDE_FLAG" == true ]]; then
            uninstall_retroiptvguide
        fi
        ;;
    *)
        show_usage
        ;;
esac
