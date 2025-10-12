#!/bin/bash
#
# install_linux_ersatztv.sh
# ---------------------------------------------------------
# Automated installer for ErsatzTV on Linux.
# Creates service user, downloads the latest build,
# installs systemd service and updater.
# ---------------------------------------------------------

set -e

SERVICE_NAME="ersatztv"
INSTALL_DIR="/opt/ersatztv"
DATA_FOLDER="/home/ersatztv/.local/share/ersatztv"
GITHUB_REPO="ErsatzTV/ErsatzTV"
UPDATER_PATH="/usr/local/bin/update_linux_ersatztv.sh"

echo "===== 🧩 Installing ErsatzTV ====="

# --- Root check --------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
   echo "❌ This installer must be run as root (sudo)."
   exit 1
fi

# --- Create user and directories ---------------------------------------------
if ! id -u ersatztv >/dev/null 2>&1; then
    echo "🔹 Creating ersatztv system user..."
    useradd -r -m -d /home/ersatztv -s /usr/sbin/nologin ersatztv
else
    echo "ℹ️ ersatztv user already exists."
fi

echo "🔹 Creating required directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$DATA_FOLDER"
chown -R ersatztv:ersatztv "$INSTALL_DIR" "$DATA_FOLDER"

# --- Detect architecture -----------------------------------------------------
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" ]]; then
    ARCH_SUFFIX="arm64"
else
    ARCH_SUFFIX="x64"
fi
echo "🔹 Detected architecture: $ARCH_SUFFIX"

# --- Download latest release -------------------------------------------------
echo "🔹 Fetching latest ErsatzTV release for Linux ($ARCH_SUFFIX)..."
LATEST_URL=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest" \
    | grep "browser_download_url" \
    | grep -E "linux-$ARCH_SUFFIX\.tar\.gz" \
    | cut -d '"' -f 4)

if [ -z "$LATEST_URL" ]; then
    echo "❌ Could not find download URL for linux-$ARCH_SUFFIX build."
    exit 1
fi

cd "$INSTALL_DIR"
echo "➡️  Downloading: $LATEST_URL"
curl -L -o ersatztv_latest.tar.gz "$LATEST_URL"

echo "🔹 Extracting ErsatzTV..."
tar -xzf ersatztv_latest.tar.gz --strip-components=1
rm ersatztv_latest.tar.gz
chown -R ersatztv:ersatztv "$INSTALL_DIR"
echo "✅ Installation files ready."

# --- Download compatible FFmpeg build ---------------------------------------
echo "🔹 Downloading compatible FFmpeg build from ErsatzTV-FFmpeg..."

FFMPEG_REPO="ErsatzTV/ErsatzTV-ffmpeg"
FFMPEG_DIR="$INSTALL_DIR/ffmpeg"
mkdir -p "$FFMPEG_DIR"

FFMPEG_URL=$(curl -s https://api.github.com/repos/$FFMPEG_REPO/releases/latest \
    | grep "browser_download_url" \
    | grep -E "linux-$ARCH_SUFFIX.*\.tar\.gz" \
    | head -n 1 \
    | cut -d '"' -f 4)

if [ -z "$FFMPEG_URL" ]; then
    echo "❌ Could not locate FFmpeg download URL for architecture: $ARCH_SUFFIX"
else
    echo "➡️  Fetching: $FFMPEG_URL"
    curl -L -o ffmpeg_bundle.tar.gz "$FFMPEG_URL"
    tar -xzf ffmpeg_bundle.tar.gz -C "$FFMPEG_DIR" --strip-components=1
    rm ffmpeg_bundle.tar.gz
    chown -R ersatztv:ersatztv "$FFMPEG_DIR"
    echo "✅ FFmpeg installed to $FFMPEG_DIR"
fi

# --- Create systemd service --------------------------------------------------
echo "🔹 Creating systemd service..."
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

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

# --- Verify service startup --------------------------------------------------
echo "🔹 Waiting for web interface..."
for i in {1..20}; do
    if curl -fs http://127.0.0.1:8409 >/dev/null 2>&1; then
        echo "✅ ErsatzTV web interface is responding (port 8409)."
        break
    fi
    sleep 2
    echo "⏳ Waiting ($((i*2))s)..."
done

if ! curl -fs http://127.0.0.1:8409 >/dev/null 2>&1; then
    echo "⚠️ Warning: ErsatzTV did not respond on port 8409 yet."
fi

# --- Create hardened updater -------------------------------------------------
echo "🔹 Installing updater script to $UPDATER_PATH ..."
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
LATEST_URL=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest" \
    | grep "browser_download_url" | grep -E "linux-$ARCH_SUFFIX\.tar\.gz" | cut -d '"' -f 4)
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

echo "===== ✅ ErsatzTV Installation Complete ====="
echo "🌐 Web Interface: http://$(hostname -I | awk '{print $1}'):8409"
echo "🔄 Update anytime with: sudo $UPDATER_PATH"
