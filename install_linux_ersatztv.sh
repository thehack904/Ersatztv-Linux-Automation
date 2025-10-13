#!/bin/bash
#
# install_linux_ersatztv.sh
# ---------------------------------------------------------
# Unified installer, updater, and uninstaller for ErsatzTV.
# Compatible with x64 and ARM64 Linux distributions.
# ---------------------------------------------------------
VERSION="v1.1.0"

set -e

if [[ "$1" == "--version" ]]; then
  echo "ErsatzTV Linux Automation Installer $VERSION"
  exit 0
fi

echo "ErsatzTV Linux Automation Installer $VERSION"

SERVICE_NAME="ersatztv"
INSTALL_DIR="/opt/ersatztv"
DATA_FOLDER="/home/ersatztv/.local/share/ersatztv"
GITHUB_REPO="ErsatzTV/ErsatzTV"
FFMPEG_REPO="ErsatzTV/ErsatzTV-ffmpeg"
UPDATER_PATH="/usr/local/bin/update_linux_ersatztv.sh"

# --- Detect architecture -----------------------------------------------------
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" ]]; then
    ARCH_SUFFIX="arm64"
else
    ARCH_SUFFIX="x64"
fi

# --- Functions ---------------------------------------------------------------

show_usage() {
    echo "ErsatzTV Linux Automation (Installer / Updater / Uninstaller)"
    echo
    echo "Usage:"
    echo "  sudo install_linux_ersatztv.sh install     # Fresh install"
    echo "  sudo install_linux_ersatztv.sh update      # Reinstall or update"
    echo "  sudo install_linux_ersatztv.sh uninstall   # Remove binaries and service"
    echo
    echo "  --version  Shows current installer version"
    echo "Optional flag for uninstall:"
    echo "  --purge    Remove all data under $DATA_FOLDER"
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
    if [[ -f "$INSTALL_DIR/ErsatzTV" ]]; then
        echo "🔍 Checking currently installed ErsatzTV version..."
        INSTALLED_VERSION=$(sudo journalctl -u $SERVICE_NAME 2>/dev/null | grep "ErsatzTV version" | tail -n 1 | awk '{print $NF}')
        if [ -z "$INSTALLED_VERSION" ]; then
            echo "⚠️  Unable to determine installed version from logs."
            INSTALLED_VERSION="(unknown)"
        fi

        LATEST_VERSION=$(curl -s https://api.github.com/repos/$GITHUB_REPO/releases/latest | grep tag_name | cut -d '"' -f 4)
        if [ -z "$LATEST_VERSION" ]; then
            echo "❌ Failed to retrieve latest release info from GitHub."
            return
        fi

        echo "   Installed: $INSTALLED_VERSION"
        echo "   Latest:    $LATEST_VERSION"

        if [[ "${INSTALLED_VERSION%%-*}" == "$LATEST_VERSION" ]]; then
            echo "✅ ErsatzTV is already up-to-date ($INSTALLED_VERSION)"
            read -rp "Would you like to reinstall this version anyway? (y/N): " confirm
            confirm=${confirm,,}
            if [[ "$confirm" != "y" && "$confirm" != "yes" ]]; then
                echo "⏹️  Installation aborted by user (already up-to-date)."
                exit 0
            fi
            echo "🔁 Proceeding with reinstall of current version..."
        else
            echo "⚠️  Update available — proceeding with new installation."
        fi
    fi
}

create_user_and_dirs() {
    if ! id -u ersatztv >/dev/null 2>&1; then
        echo "🔹 Creating ersatztv system user..."
        useradd -r -m -d /home/ersatztv -s /usr/sbin/nologin ersatztv
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

download_ersatztv() {
    echo "🔹 Downloading latest ErsatzTV release for Linux ($ARCH_SUFFIX)..."
    LATEST_URL=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest" \
        | grep "browser_download_url" | grep -E "linux-$ARCH_SUFFIX\.tar\.gz" | cut -d '"' -f 4)
    if [ -z "$LATEST_URL" ]; then
        echo "❌ Could not find a matching ErsatzTV release for $ARCH_SUFFIX"
        exit 1
    fi
    cd "$INSTALL_DIR"
    echo "➡️  Fetching: $LATEST_URL"
    curl -L -o ersatztv_latest.tar.gz "$LATEST_URL"
    tar -xzf ersatztv_latest.tar.gz --strip-components=1
    rm ersatztv_latest.tar.gz
    chown -R ersatztv:ersatztv "$INSTALL_DIR" /home/ersatztv/.local
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
        rm ffmpeg_bundle.tar.xz
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
    cat <<EOF > /etc/systemd/system/${SERVICE_NAME}.service
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
Environment=HOME=/home/ersatztv
Environment=PATH=$FFMPEG_PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF
    rm -f /tmp/ffmpeg_path_detected
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl restart $SERVICE_NAME
}

install_updater() {
    echo "🔹 Installing updater script..."
    cat <<'EOS' > $UPDATER_PATH
#!/bin/bash
set -e
SERVICE_NAME="ersatztv"
INSTALL_DIR="/opt/ersatztv"
GITHUB_REPO="ErsatzTV/ErsatzTV"
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
rm ersatztv_latest.tar.gz
chown -R ersatztv:ersatztv "$INSTALL_DIR"
sudo sed -i 's/^Restart=no/Restart=on-failure/' /etc/systemd/system/${SERVICE_NAME}.service 2>/dev/null || true
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
    echo "🔹 Stopping and disabling service..."
    systemctl stop $SERVICE_NAME 2>/dev/null || true
    systemctl disable $SERVICE_NAME 2>/dev/null || true
    rm -f /etc/systemd/system/${SERVICE_NAME}.service
    systemctl daemon-reload
    echo "🔹 Removing application files..."
    rm -rf "$INSTALL_DIR" "$UPDATER_PATH"
    echo
    echo "🧩 ErsatzTV data is stored in: $DATA_FOLDER"
    echo "This folder contains all configuration, databases, logs, and secrets."
    echo
    if [[ "$purge_flag" == "--purge" ]]; then
        echo "⚠️ Purge mode enabled — removing ersatztv user and home directory..."
        userdel -r ersatztv 2>/dev/null || true
        echo "✅ ersatztv user and all data removed."
    else
        read -rp "Do you also want to remove the 'ersatztv' user and its home directory? (y/N): " confirm
        confirm=${confirm,,}
        if [[ "$confirm" == "y" || "$confirm" == "yes" ]]; then
            echo "⚠️ Removing ersatztv user and all associated data..."
            userdel -r ersatztv 2>/dev/null || true
            echo "✅ ersatztv user and home directory removed."
        else
            echo "ℹ️ Keeping ersatztv user and home directory at /home/ersatztv"
        fi
    fi
    echo "✅ ErsatzTV has been uninstalled."
}

# --- Main Execution ----------------------------------------------------------
ACTION="$1"

case "$ACTION" in
    install|update)
        check_root
        check_existing_version
        create_user_and_dirs
        download_ersatztv
        download_ffmpeg
        create_service
        install_updater
        verify_startup
        echo "✅ Installation complete!"
        ;;
    uninstall)
        check_root
        uninstall_ersatztv "$2"
        ;;
    *)
        show_usage
        ;;
esac
