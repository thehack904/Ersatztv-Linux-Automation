#!/bin/bash
#
# install_linux_ersatztv.sh
# ---------------------------------------------------------
# Unified installer, updater, and uninstaller for ErsatzTV.
# Compatible with x64 and ARM64 Linux distributions.
# ---------------------------------------------------------
VERSION="v1.2.1"

set -e

if [[ "$1" == "--version" ]]; then
  echo "ErsatzTV Linux Automation Installer $VERSION"
  exit 0
fi

echo "ErsatzTV Linux Automation Installer $VERSION"

SERVICE_NAME="ersatztv"
INSTALL_DIR="/opt/ersatztv"
DATA_FOLDER="/home/ersatztv/.local/share/ersatztv"
GITHUB_REPO="ErsatzTV/legacy"
FFMPEG_REPO="ErsatzTV/ErsatzTV-ffmpeg"
UPDATER_PATH="/usr/local/bin/update_linux_ersatztv.sh"

# --- Version selection -------------------------------------------------------
# The default tag matches the recommended GHCR image: ghcr.io/ersatztv/legacy:develop
DEFAULT_ERSATZTV_TAG="develop"
ERSATZTV_IMAGE_BASE="ghcr.io/ersatztv/legacy"
ERSATZTV_TAG_FILE="$INSTALL_DIR/.installed_tag"
SELECTED_TAG=""

# --- Detect architecture -----------------------------------------------------
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" ]]; then
    ARCH_SUFFIX="arm64"
else
    ARCH_SUFFIX="x64"
fi

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
    echo "ErsatzTV Linux Automation (Installer / Updater / Uninstaller)"
    echo
    echo "Usage:"
    echo "  sudo install_linux_ersatztv.sh install [--retroiptvguide]   # Install ErsatzTV (and optionally RetroIPTVGuide)"
    echo "  sudo install_linux_ersatztv.sh update                       # Update or reinstall ErsatzTV"
    echo "  sudo install_linux_ersatztv.sh uninstall [--purge]          # Remove binaries and service"
    echo
    echo "  --version  Shows current installer version"
    echo
    echo "Optional flags:"
    echo "  --retroiptvguide  Install RetroIPTVGuide after ErsatzTV setup"
    echo "  --purge           Remove all data under $DATA_FOLDER during uninstall"
    echo
    echo "Version selection:"
    echo "  Set the ERSATZTV_VERSION environment variable to skip the interactive prompt."
    echo "  Examples:"
    echo "    ERSATZTV_VERSION=develop   sudo -E bash install_linux_ersatztv.sh install"
    echo "    ERSATZTV_VERSION=26.3      sudo -E bash install_linux_ersatztv.sh install"
    echo "    ERSATZTV_VERSION=26.3      sudo -E bash install_linux_ersatztv.sh update"
    echo
    echo "  Available tags: develop (default), latest, 26.4 (⚠️ buggy), 26.3, or any GitHub release tag."
    exit 1
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
        if [[ -f "$ERSATZTV_TAG_FILE" ]]; then
            local current_tag
            current_tag=$(cat "$ERSATZTV_TAG_FILE" 2>/dev/null || echo "")
            if [[ -n "$current_tag" ]]; then
                echo "   Installed tag : $current_tag  (${ERSATZTV_IMAGE_BASE}:${current_tag})"
            fi
        else
            # Fall back to journal-based version detection for pre-v1.2.1 installs
            local log_version
            log_version=$(journalctl -u $SERVICE_NAME 2>/dev/null | grep "ErsatzTV version" | tail -n 1 | awk '{print $NF}' || echo "")
            if [[ -n "$log_version" ]]; then
                echo "   Installed version: $log_version"
            else
                echo "   ⚠️  Cannot determine installed version from logs."
            fi
        fi
    fi
}

# --- Warn about tags with known issues ----------------------------------------
_warn_if_known_buggy_tag() {
    local tag="$1"
    if [[ "$tag" == "26.4" ]]; then
        echo ""
        echo "  ⚠️  WARNING: Tag '26.4' has a known WebUI/playout creation bug."
        echo "     It is strongly recommended to use '26.3' or 'develop' instead."
        echo "     Proceeding in 5 seconds (press Ctrl+C to abort)..."
        sleep 5
        echo ""
    fi
}

# --- Stage 2: Version selection -----------------------------------------------
select_ersatztv_version() {
    # Non-interactive: honour the ERSATZTV_VERSION environment variable
    if [[ -n "${ERSATZTV_VERSION:-}" ]]; then
        local env_tag="${ERSATZTV_VERSION// /}"   # strip any accidental whitespace
        if [[ -z "$env_tag" ]]; then
            echo "⚠️  ERSATZTV_VERSION is set but blank — using default: $DEFAULT_ERSATZTV_TAG"
            SELECTED_TAG="$DEFAULT_ERSATZTV_TAG"
        else
            SELECTED_TAG="$env_tag"
            echo "ℹ️  ERSATZTV_VERSION is set — using tag: $SELECTED_TAG  (${ERSATZTV_IMAGE_BASE}:${SELECTED_TAG})"
        fi
        _warn_if_known_buggy_tag "$SELECTED_TAG"
        return
    fi

    # Show installed tag for context (downgrade awareness)
    local installed_tag=""
    if [[ -f "$ERSATZTV_TAG_FILE" ]]; then
        installed_tag=$(cat "$ERSATZTV_TAG_FILE" 2>/dev/null || echo "")
    fi

    # Fetch the previous release from GitHub (only when a versioned tag is installed)
    local prev_tag=""
    if [[ -n "$installed_tag" ]] && _is_versioned_tag "$installed_tag"; then
        echo "🔍 Checking available releases..."
        prev_tag=$(_fetch_previous_github_tag "$installed_tag")
    fi

    echo ""
    echo "📦 Select which ErsatzTV version to install:"
    echo "   1) develop  — latest development build  [DEFAULT, recommended]"
    echo "   2) latest   — latest stable GitHub release"
    echo "   3) 26.4     — release 26.4  ⚠️  known WebUI/playout bug"
    echo "   4) 26.3     — release 26.3  (stable)"
    echo "   5) custom   — enter any GitHub release tag manually"
    if [[ -n "$prev_tag" ]]; then
        echo "   6) ⬇️  downgrade  — install $prev_tag (one version behind currently installed $installed_tag)"
    fi
    echo ""
    if [[ -n "$installed_tag" ]]; then
        echo "   Currently installed: $installed_tag"
        echo ""
    fi

    local choice=""
    local prompt_range="1-5"
    [[ -n "$prev_tag" ]] && prompt_range="1-6"
    if [ -t 0 ]; then
        read -rp "Enter choice [$prompt_range, or press Enter for default 'develop']: " choice
    fi
    choice="${choice:-1}"

    case "$choice" in
        1|develop)  SELECTED_TAG="develop" ;;
        2|latest)   SELECTED_TAG="latest"  ;;
        3|26.4)     SELECTED_TAG="26.4"    ;;
        4|26.3)     SELECTED_TAG="26.3"    ;;
        5|custom)
            if [ -t 0 ]; then
                read -rp "Enter custom tag (e.g. 26.2, v0.8.0): " custom_tag
                custom_tag="${custom_tag// /}"
                if [[ -z "$custom_tag" ]]; then
                    echo "⚠️  No tag entered — using default: $DEFAULT_ERSATZTV_TAG"
                    SELECTED_TAG="$DEFAULT_ERSATZTV_TAG"
                else
                    SELECTED_TAG="$custom_tag"
                fi
            else
                echo "⚠️  Non-interactive mode with no ERSATZTV_VERSION set — using default: $DEFAULT_ERSATZTV_TAG"
                SELECTED_TAG="$DEFAULT_ERSATZTV_TAG"
            fi
            ;;
        6)
            if [[ -n "$prev_tag" ]]; then
                SELECTED_TAG="$prev_tag"
            else
                echo "⚠️  Invalid choice '$choice' — using default: $DEFAULT_ERSATZTV_TAG"
                SELECTED_TAG="$DEFAULT_ERSATZTV_TAG"
            fi
            ;;
        *)
            echo "⚠️  Invalid choice '$choice' — using default: $DEFAULT_ERSATZTV_TAG"
            SELECTED_TAG="$DEFAULT_ERSATZTV_TAG"
            ;;
    esac

    # Announce the operation type and warn clearly when downgrading
    if [[ -n "$installed_tag" && "$SELECTED_TAG" != "$installed_tag" ]]; then
        if _tag_is_older_than "$SELECTED_TAG" "$installed_tag"; then
            echo ""
            echo "  ⬇️  DOWNGRADE: $installed_tag → $SELECTED_TAG"
            echo "  ⚠️  The ErsatzTV database schema is generally NOT backward-compatible."
            echo "     Your settings and config files will be preserved."
            echo "     A backup of your data folder will be created automatically before"
            echo "     the downgrade proceeds."
        else
            echo "ℹ️  Changing installed tag: $installed_tag → $SELECTED_TAG"
            echo "   Your config and data will NOT be removed."
        fi
    fi

    _warn_if_known_buggy_tag "$SELECTED_TAG"
    echo "✅ Selected tag: $SELECTED_TAG  (${ERSATZTV_IMAGE_BASE}:${SELECTED_TAG})"
    echo ""
}

create_user_and_dirs() {
    if ! id -u ersatztv >/dev/null 2>&1; then
        echo "🔹 Creating ersatztv system user..."
        useradd -r -m -d /home/ersatztv -s "$NOLOGIN_PATH" ersatztv
    else
        echo "ℹ️ ersatztv user already exists."
    fi

    # Create home & data with correct owner/mode from the start
    install -d -o ersatztv -g ersatztv -m 750 /home/ersatztv
    install -d -o ersatztv -g ersatztv -m 700 /home/ersatztv/.local
    install -d -o ersatztv -g ersatztv -m 700 /home/ersatztv/.local/share
    install -d -o ersatztv -g ersatztv -m 700 "$DATA_FOLDER"
    install -d -o ersatztv -g ersatztv -m 700 "$DATA_FOLDER/logs"
    install -d -o ersatztv -g ersatztv -m 755 "$INSTALL_DIR"
}

# Convert a bare version number (e.g. "26.4") to the GitHub tag format used by
# the ErsatzTV/legacy repo (e.g. "v26.4.0"). Tags that already start with "v",
# or do not match the simple NN.NN pattern, are returned unchanged.
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

download_ffmpeg() {
    echo "🔹 Downloading compatible FFmpeg build..."
    mkdir -p "$INSTALL_DIR/ffmpeg"
    FFMPEG_URL=$(curl -s "https://api.github.com/repos/$FFMPEG_REPO/releases/latest" \
        | grep "browser_download_url" | grep -E "linux(64|arm64).*\.tar\.xz" | grep -i "$ARCH_SUFFIX" | head -n 1 | cut -d '"' -f 4)
    echo "➡️  Fetching: $FFMPEG_URL"
    curl -L -o ffmpeg_bundle.tar.xz "$FFMPEG_URL"
    if [ -f "ffmpeg_bundle.tar.xz" ]; then
        echo "🔹 Extracting FFmpeg..."
        tar -xf ffmpeg_bundle.tar.xz -C "$INSTALL_DIR/ffmpeg" --strip-components=1
        rm -f ffmpeg_bundle.tar.xz
        chown -R ersatztv:ersatztv "$INSTALL_DIR/ffmpeg"
        if [ -d "$INSTALL_DIR/ffmpeg/bin" ]; then
            FFMPEG_PATH="$INSTALL_DIR/ffmpeg/bin"
        else
            FFMPEG_PATH="$INSTALL_DIR/ffmpeg"
        fi
        echo "$FFMPEG_PATH" > /tmp/ffmpeg_path_detected
        echo "✅ FFmpeg installed to $FFMPEG_PATH"
    else
        echo "❌ FFmpeg download failed."
    fi
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
    preflight_check "$DETECTED_BINARY"
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl restart $SERVICE_NAME
    configure_firewall
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
    echo "🔹 Installing updater script..."
    cat <<'EOS' > $UPDATER_PATH
#!/bin/bash
set -e
SERVICE_NAME="ersatztv"
INSTALL_DIR="/opt/ersatztv"
DATA_FOLDER="/home/ersatztv/.local/share/ersatztv"
GITHUB_REPO="ErsatzTV/legacy"
BACKUP_DIR="/opt/ersatztv_backup_$(date +%Y%m%d_%H%M%S)"
LOCK_FILE="/tmp/ersatztv_update.lock"
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" ]]; then ARCH_SUFFIX="arm64"; else ARCH_SUFFIX="x64"; fi
[ -f "$LOCK_FILE" ] && { echo "❌ Update already running."; exit 1; }
touch "$LOCK_FILE"; trap 'rm -f "$LOCK_FILE"' EXIT
echo "===== 🧩 ErsatzTV Updater ====="
sudo sed -i 's/^Restart=.*/Restart=no/' /etc/systemd/system/${SERVICE_NAME}.service 2>/dev/null || true
sudo systemctl daemon-reload
sudo systemctl stop $SERVICE_NAME || true
mkdir -p "$BACKUP_DIR"
cp -r "$INSTALL_DIR"/* "$BACKUP_DIR"/ 2>/dev/null || true
LATEST_URL=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | grep "browser_download_url" | grep -E "linux-$ARCH_SUFFIX\.tar\.gz" | cut -d '"' -f 4)
[ -z "$LATEST_URL" ] && { echo "❌ Could not find download URL."; exit 1; }
cd "$INSTALL_DIR"
curl -L -o ersatztv_latest.tar.gz "$LATEST_URL"
tar -xzf ersatztv_latest.tar.gz --strip-components=1
rm -f ersatztv_latest.tar.gz
chown -R ersatztv:ersatztv "$INSTALL_DIR"
# Binary detection is inlined here because this script lives in a single-quoted
# heredoc in the installer and cannot call the installer's detect_ersatztv_binary().
DETECTED_BINARY=""
if [[ -x "$INSTALL_DIR/ErsatzTV" ]]; then
    DETECTED_BINARY="$INSTALL_DIR/ErsatzTV"
elif [[ -x "$INSTALL_DIR/ErsatzTV-Legacy" ]]; then
    DETECTED_BINARY="$INSTALL_DIR/ErsatzTV-Legacy"
fi
if [[ -z "$DETECTED_BINARY" ]]; then
    echo "❌ Cannot find ErsatzTV binary in $INSTALL_DIR after update (tried ErsatzTV, ErsatzTV-Legacy)."
    exit 1
fi
echo "✅ Detected binary: $DETECTED_BINARY"
sudo sed -i "s|^ExecStart=.*|ExecStart=$DETECTED_BINARY --data-folder $DATA_FOLDER|" /etc/systemd/system/${SERVICE_NAME}.service 2>/dev/null || true
sudo sed -i 's/^Restart=no/Restart=on-failure/' /etc/systemd/system/${SERVICE_NAME}.service 2>/dev/null || true
# Preflight validation is inlined here because this script lives in a single-quoted
# heredoc in the installer and cannot call the installer's preflight_check() function.
echo "🔍 Running preflight validation..."
PREFLIGHT_ERRORS=0
if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "❌ Install directory $INSTALL_DIR does not exist."
    PREFLIGHT_ERRORS=$((PREFLIGHT_ERRORS + 1))
else
    echo "✅ Install directory $INSTALL_DIR exists."
fi
if [[ ! -e "$DETECTED_BINARY" ]]; then
    echo "❌ Expected executable $DETECTED_BINARY does not exist."
    PREFLIGHT_ERRORS=$((PREFLIGHT_ERRORS + 1))
else
    echo "✅ Executable $DETECTED_BINARY exists."
fi
if [[ ! -x "$DETECTED_BINARY" ]]; then
    echo "❌ Executable $DETECTED_BINARY does not have execute permission."
    PREFLIGHT_ERRORS=$((PREFLIGHT_ERRORS + 1))
else
    echo "✅ Executable $DETECTED_BINARY has execute permission."
fi
if [[ ! -d "$DATA_FOLDER" ]]; then
    echo "❌ Data folder $DATA_FOLDER does not exist."
    PREFLIGHT_ERRORS=$((PREFLIGHT_ERRORS + 1))
else
    echo "✅ Data folder $DATA_FOLDER exists."
fi
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
if [[ -f "$SERVICE_FILE" ]]; then
    SERVICE_EXEC=$(grep -E '^ExecStart=' "$SERVICE_FILE" | sed 's/^ExecStart=//' | awk '{print $1}')
    if [[ "$SERVICE_EXEC" != "$DETECTED_BINARY" ]]; then
        echo "❌ Service unit ExecStart ($SERVICE_EXEC) does not match installed binary ($DETECTED_BINARY)."
        PREFLIGHT_ERRORS=$((PREFLIGHT_ERRORS + 1))
    else
        echo "✅ Service unit references the installed binary."
    fi
else
    echo "⚠️  Service unit $SERVICE_FILE not found (skipping ExecStart check)."
fi
if [[ -d "$INSTALL_DIR" ]]; then
    INSTALL_OWNER=$(stat -c '%U' "$INSTALL_DIR")
    if [[ "$INSTALL_OWNER" != "ersatztv" ]]; then
        echo "❌ $INSTALL_DIR is owned by '$INSTALL_OWNER', expected 'ersatztv'."
        PREFLIGHT_ERRORS=$((PREFLIGHT_ERRORS + 1))
    else
        echo "✅ $INSTALL_DIR is owned by ersatztv."
    fi
fi
if [[ -d "$DATA_FOLDER" ]]; then
    DATA_OWNER=$(stat -c '%U' "$DATA_FOLDER")
    if [[ "$DATA_OWNER" != "ersatztv" ]]; then
        echo "❌ $DATA_FOLDER is owned by '$DATA_OWNER', expected 'ersatztv'."
        PREFLIGHT_ERRORS=$((PREFLIGHT_ERRORS + 1))
    else
        echo "✅ $DATA_FOLDER is owned by ersatztv."
    fi
fi
if [[ "$PREFLIGHT_ERRORS" -gt 0 ]]; then
    echo "❌ Preflight validation failed with $PREFLIGHT_ERRORS error(s). Service restart aborted."
    exit 1
fi
echo "✅ All preflight checks passed."
sudo systemctl daemon-reload
sudo systemctl start $SERVICE_NAME
for i in {1..20}; do
    if curl -fs http://127.0.0.1:8409 >/dev/null 2>&1; then
        echo "✅ ErsatzTV web interface is up."
        exit 0
    fi
    sleep 2
done
echo "⚠️ Web interface not detected; check logs."
EOS
    chmod +x $UPDATER_PATH
    echo "✅ Updater installed at $UPDATER_PATH"
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

uninstall_ersatztv() {
    local purge_flag="$1"
    local retro_flag="$2"

    echo "🔹 Stopping and disabling ErsatzTV service..."
    systemctl stop $SERVICE_NAME 2>/dev/null || true
    systemctl disable $SERVICE_NAME 2>/dev/null || true
    rm -f /etc/systemd/system/${SERVICE_NAME}.service
    systemctl daemon-reload

    echo "🔹 Removing ErsatzTV application files..."
    rm -rf "$INSTALL_DIR" "$UPDATER_PATH"
    echo
    echo "🧩 ErsatzTV data is stored in: $DATA_FOLDER"
    echo "This folder contains all configuration, databases, logs, and secrets."
    echo

    if [[ "$purge_flag" == "--purge" ]]; then
        echo "⚠️ Purge mode enabled — removing ersatztv user and home directory..."
        userdel -r ersatztv 2>/dev/null || true
        echo "✅ ersatztv user and all data removed."
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
    echo "🌐 ErsatzTV web interface: http://${server_ip}:8409"
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
    echo "Use the following to manage services:"
    echo "   sudo systemctl status ersatztv"
    if [[ "$1" == "retro" ]]; then
        echo "   sudo systemctl status iptv-server"
    fi
    echo ""
    echo "============================================================"
}

# --- Main Execution ----------------------------------------------------------
ACTION="$1"
OPTION1="$2"
OPTION2="$3"

case "$ACTION" in
    install|update)
        check_root
        check_existing_version
        select_ersatztv_version
        create_user_and_dirs
        download_ersatztv
        download_ffmpeg
        create_service
        install_updater
        verify_startup

	if [[ "$OPTION1" == "--retroiptvguide" || "$OPTION2" == "--retroiptvguide" ]]; then
            install_retroiptvguide
            show_final_summary "retro"
        else
            show_final_summary
        fi
        ;;
    uninstall)
        check_root
        uninstall_ersatztv "$OPTION1" "$OPTION2"
        if [[ "$OPTION1" == "--retroiptvguide" || "$OPTION2" == "--retroiptvguide" ]]; then
            uninstall_retroiptvguide
        fi
        ;;
    *)
        show_usage
        ;;
esac
