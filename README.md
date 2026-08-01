# ErsatzTV-Linux-Automation

![Version](https://img.shields.io/badge/version-v1.3.0-blue?style=for-the-badge)
![License](https://img.shields.io/badge/license-zlib-green?style=for-the-badge)
![Platform](https://img.shields.io/badge/platform-linux-lightgrey?style=for-the-badge)

**Deploy, manage, and update ErsatzTV Legacy with a single command.**

> [!IMPORTANT]
> **ErsatzTV Legacy only:** This project installs, upgrades, repairs, and removes **ErsatzTV Legacy** from the [`ErsatzTV/legacy`](https://github.com/ErsatzTV/legacy) repository. It does **not** support, install, upgrade, migrate, or manage **ErsatzTV Next**. Do not use this automation on an ErsatzTV Next installation.

ErsatzTV-Linux-Automation is a full automation toolkit for installing, managing, and updating [ErsatzTV Legacy](https://github.com/ErsatzTV/legacy) on Linux systems.  
It provides a one-command installer, hardened updater, and complete systemd integration to make ErsatzTV deployment truly hands-free.

---

## Compatibility scope

This automation is specifically designed for **ErsatzTV Legacy** and its Linux release artifacts. Release discovery, version selection, managed FFmpeg compatibility, systemd service creation, upgrades, repair, and uninstall behavior all target the [`ErsatzTV/legacy`](https://github.com/ErsatzTV/legacy) project.

**ErsatzTV Next is not supported.** This project does not query ErsatzTV Next releases, recognize its installation layout, or provide a Legacy-to-Next migration path.

---

## 🧩 Features

- ⚙️ **One-Command Installer** – Installs ErsatzTV directly from the latest GitHub release.
- 👤 **Dedicated System User** – Runs safely under its own `ersatztv` account.
- 📂 **Persistent Data Folder** – Stores all settings and database files in `/home/ersatztv/.local/share/ersatztv`.
- 🧠 **Architecture Detection** – Automatically installs the correct `x64` or `ARM64` binary.
- 🧩 **Release-Driven FFmpeg Compatibility** – Inspects selected ErsatzTV release metadata (notes + assets) to resolve the required managed `ErsatzTV-ffmpeg` version.
- 🔁 **Hardened Updater** – Includes rollback protection, graceful shutdown, and lock-file safety.
- 🔒 **Data-Safe Updates** – Leaves your database and configuration untouched during upgrades.
- 🚀 **Systemd Integration** – Creates and enables the service automatically for seamless boot startup.
- 🧱 **Fedora/RHEL Compatibility** – Detects Fedora or RHEL systems, installs required packages (`curl`, `tar`, `git`), and automatically adjusts SELinux file contexts.
- 💠 **Ubuntu/Debian Compatibility** – Works seamlessly with Debian-based distributions using built-in `apt`, and supports systems with or without `ufw`.
- 🔥 **Automatic Firewall Configuration** – Opens port `8409/tcp` during installation and removes it on uninstall for both `firewalld` and `ufw` systems.
- 🏷️ **Version / Tag Selection** – Choose `develop`, `latest`, or one of the current four published Legacy releases; exact tags remain available non-interactively through `ERSATZTV_VERSION`.
- 🧠 **Compatibility Cache** – Stores resolved release-to-FFmpeg compatibility data in `/var/lib/ersatztv-linux-automation/compatibility/`.

---

## 🏷️ Version / Tag Selection

By default, the installer downloads the latest **develop** build. During installation or upgrade, it presents this menu:

```
📦 Select which ErsatzTV Legacy version to install:
   1) develop  — latest development build  [DEFAULT, recommended]
   2) latest   — latest stable GitHub release
   3) custom   — choose from the current and previous three releases
   Q) cancel   — exit without making changes
```

Older releases are no longer listed as dedicated menu choices. The custom menu lists only the current published Legacy release and the three immediately preceding Legacy releases. That submenu includes **B) Back** to return to the main version menu and **Q) Cancel** to exit before installation or upgrade changes begin. An exact Legacy release tag can also be supplied through `ERSATZTV_VERSION`. ErsatzTV Next releases are never listed or selected.

### Non-interactive / scripted installs

Set `ERSATZTV_VERSION` to bypass the prompt:

```bash
ERSATZTV_VERSION=develop sudo -E ersatztv-linux-automation --install
ERSATZTV_VERSION=latest sudo -E ersatztv-linux-automation --upgrade
ERSATZTV_VERSION=v26.7.1 sudo -E ersatztv-linux-automation --upgrade
```

The installer records the selected tag in `/opt/ersatztv/.installed_tag` and displays it on later runs.

### FFmpeg health-check warning

The automation installs and validates its managed FFmpeg bundle but does **not** modify ErsatzTV's database or saved application settings. After ErsatzTV starts, the installer checks which executables ErsatzTV reports using.

When the health check detects `/usr/bin/ffmpeg`, `/usr/bin/ffprobe`, or cannot confirm the selected executables, the final summary instructs the user to open ErsatzTV **Settings** and verify:

```text
FFmpeg Path:  /opt/ersatztv/ffmpeg/bin/ffmpeg
FFprobe Path: /opt/ersatztv/ffmpeg/bin/ffprobe
```

After saving those settings, restart ErsatzTV:

```bash
sudo systemctl restart ersatztv
```

## 🚀 Quick Install (One-Liner)

To install **ErsatzTV Legacy** automatically on a supported Linux system, run:

```bash
curl -sSL https://raw.githubusercontent.com/thehack904/ErsatzTV-Linux-Automation/main/ersatztv-linux-automation.sh | sudo bash -s -- --install
```

Manual Download / Execute:
```bash
wget https://raw.githubusercontent.com/thehack904/ErsatzTV-Linux-Automation/main/ersatztv-linux-automation.sh
sudo bash ersatztv-linux-automation.sh --install
```

When complete:
- ErsatzTV Legacy will be installed to `/opt/ersatztv`
- Downloads the managed FFmpeg version required by the selected ErsatzTV Legacy release
- It will run as the `ersatztv` user
- Automatically configures firewall (if active)
- Web interface available at:  http://<server-ip>:8409
  
Optional (add RetroIPTVGuide):
```bash
curl -sSL https://raw.githubusercontent.com/thehack904/ErsatzTV-Linux-Automation/main/ersatztv-linux-automation.sh | sudo bash -s -- --install --retroiptvguide
```
When complete:
- [RetroIPTVGuide](https://github.com/thehack904/RetroIPTVGuide) will be installed

---

## 🔁 Updating ErsatzTV Legacy

> This upgrade workflow is for **ErsatzTV Legacy only**. It must not be used to update ErsatzTV Next.

Run the canonical lifecycle command anytime:

(One-Liner)
```bash
curl -sSL https://raw.githubusercontent.com/thehack904/ErsatzTV-Linux-Automation/main/ersatztv-linux-automation.sh | sudo bash -s -- --upgrade
```
Manual
```bash
  sudo ersatztv-linux-automation --upgrade
```

**Updater Features**
- Gracefully stops the systemd service  
- Disables auto-restart during update  
- Detects and installs the correct latest build  
- Resolves required managed FFmpeg from selected ErsatzTV release data
- Upgrades FFmpeg only when required (or when managed binaries are missing/invalid)
- Automatically restarts and verifies the web interface  
- Rolls back automatically if an update fails  

### Managed FFmpeg compatibility behavior

- FFmpeg compatibility is resolved from `ErsatzTV/legacy` release metadata before live files are changed.
- Official links to `ErsatzTV/ErsatzTV-ffmpeg/releases/tag/<version>` are treated as highest-confidence requirements.
- Structured release-note statements like `Bundled FFmpeg was upgraded from 7.1 to 8.1.2` are parsed.
- If a release has no explicit FFmpeg change, compatibility may be inherited from earlier inspected releases.
- Built-in fallback mapping includes `v26.7.0 -> 8.1.2`.
- Unknown/ambiguous compatibility fails safely before service stop or file replacement.
- The managed FFmpeg bundle is validated using `/opt/ersatztv/ffmpeg*` binaries (`ffmpeg -version`, `ffprobe -version`).
- System package FFmpeg (for example `/usr/bin/ffmpeg`) is not used as a replacement for the managed bundle.

Check the installed managed versions regardless of archive layout:
```bash
FFMPEG_DIR=/opt/ersatztv/ffmpeg
[[ -x "$FFMPEG_DIR/bin/ffmpeg" ]] && FFMPEG_DIR="$FFMPEG_DIR/bin"
"$FFMPEG_DIR/ffmpeg" -version
"$FFMPEG_DIR/ffprobe" -version
```

Compatibility wrappers are still installed temporarily:
- `install_linux_ersatztv.sh` → `ersatztv-linux-automation --install`
- `update_linux_ersatztv.sh` → `ersatztv-linux-automation --upgrade`

Both print a deprecation warning. The repository-level `install_linux_ersatztv.sh` also remains a standalone bootstrapper so previously published one-line install commands continue to work.

### Upgrading from v1.2.x

Use the new canonical script for the first v1.3.0 upgrade:

```bash
curl -sSL https://raw.githubusercontent.com/thehack904/Ersatztv-Linux-Automation/main/ersatztv-linux-automation.sh | sudo bash -s -- --upgrade
```

The upgrade installs the canonical management command at:

```text
/usr/local/sbin/ersatztv-linux-automation
```

After that, future upgrades can be run locally with:

```bash
sudo ersatztv-linux-automation --upgrade
```

---

## 🩹 Repairing an ErsatzTV Legacy Installation

Use repair when the Legacy installation exists but managed files, permissions, the service definition, lifecycle commands, or the managed FFmpeg bundle need to be restored:

```bash
sudo ersatztv-linux-automation --repair
```

The repair workflow recreates or corrects the dedicated system user and required directories, ownership and permissions, the systemd service, managed FFmpeg when missing or invalid, and the installed lifecycle commands and compatibility wrappers. It preserves the ErsatzTV database and configuration under `/home/ersatztv/.local/share/ersatztv`.

The repair action targets ErsatzTV Legacy only and does not migrate or modify ErsatzTV Next installations.

---
## 🧨 Automated Uninstalling ErsatzTV Legacy

> The uninstall workflow targets the Legacy installation layout created by this project. It does not detect or remove ErsatzTV Next.

Run the canonical lifecycle command to remove ErsatzTV Legacy.

The standard uninstall removes the application and service, then asks whether to preserve `/home/ersatztv`, which contains the current settings and database for a later reinstall.

Partial Uninstall (Save user data/configs)
```bash
  sudo ersatztv-linux-automation --uninstall
```

Full Uninstall (Nothing Saved)

One-Liner
```bash
curl -sSL https://raw.githubusercontent.com/thehack904/ErsatzTV-Linux-Automation/main/ersatztv-linux-automation.sh | sudo bash -s -- --uninstall --purge
```

Local
```bash
  sudo ersatztv-linux-automation --uninstall --purge
```

Optional (remove RetroIPTVGuide):
```bash
curl -sSL https://raw.githubusercontent.com/thehack904/ErsatzTV-Linux-Automation/main/ersatztv-linux-automation.sh | sudo bash -s -- --uninstall --purge --retroiptvguide
```

During uninstall, the script will also remove the open firewall rule (port `8409/tcp`) if present.

---

## 🛠️ Troubleshooting

### Service fails to start — `status=203/EXEC`

**What it means**

`systemd` exit code `203/EXEC` means the binary listed in `ExecStart=` inside the service unit cannot be found or executed. This typically happens after an update renames the binary (e.g. from `ErsatzTV-Legacy` to `ErsatzTV`) while the service file still points to the old path.

---

**Step 1 – Check what binaries are actually installed**

```bash
ls -lah /opt/ersatztv/
```

Look for the executable file. Depending on the release, it will be named either `ErsatzTV` or `ErsatzTV-Legacy`.

---

**Step 2 – Check what path the service is currently using**

```bash
systemctl cat ersatztv
```

Find the `ExecStart=` line. Confirm whether the path it references matches a file that actually exists in `/opt/ersatztv/`.

---

**Step 3 – Correct `ExecStart` to point to the real binary**

If the service still references the old `ErsatzTV-Legacy` name but only `ErsatzTV` exists, run:

```bash
sudo sed -i 's|/opt/ersatztv/ErsatzTV-Legacy|/opt/ersatztv/ErsatzTV|g' /etc/systemd/system/ersatztv.service
```

If the actual binary name is different (confirm with `ls -lah /opt/ersatztv/` from Step 1), open the file directly and update the `ExecStart=` line to match the exact binary name you found:

```bash
sudo nano /etc/systemd/system/ersatztv.service
# Change the ExecStart= line to:
#   ExecStart=/opt/ersatztv/<actual-binary-name> --data-folder /home/ersatztv/.local/share/ersatztv
```

> ⚠️ **Do NOT delete or modify `/home/ersatztv/.local/share/ersatztv/`** during this repair.  
> That folder contains your database, channel configurations, and all settings.  
> Deleting it will permanently erase your ErsatzTV data.

---

**Step 4 – Reload systemd and restart the service**

```bash
sudo systemctl daemon-reload
sudo systemctl restart ersatztv
sudo systemctl status ersatztv --no-pager
```

A successful start will show `Active: active (running)`. If the service is still failing, re-run **Step 1** to confirm the exact binary name and update `ExecStart=` accordingly in `/etc/systemd/system/ersatztv.service`.

---

For details, see the [CHANGELOG](CHANGELOG.md).

## 🪪 License

This project is licensed under the **zLib License**, allowing free use, modification, and redistribution — including for commercial purposes — provided attribution and license text are retained.

---

## 💬 Credits

- **ErsatzTV-Linux-Automation** maintained by *thehack904*  
- **ErsatzTV Legacy** developed by [Jason G. Dove and contributors](https://github.com/ErsatzTV/legacy)
- **RetroIPTVGuide** developed by [thehack904](https://github.com/thehack904/RetroIPTVGuide)

---
