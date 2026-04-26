# ErsatzTV-Linux-Automation

![Version](https://img.shields.io/badge/version-v1.2.1-blue?style=for-the-badge)
![License](https://img.shields.io/badge/license-zlib-green?style=for-the-badge)
![Platform](https://img.shields.io/badge/platform-linux-lightgrey?style=for-the-badge)

**Deploy, manage, and update ErsatzTV with a single command.**

ErsatzTV-Linux-Automation is a full automation toolkit for installing, managing, and updating [ErsatzTV](https://github.com/ErsatzTV/ErsatzTV) on Linux systems.  
It provides a one-command installer, hardened updater, and complete systemd integration to make ErsatzTV deployment truly hands-free.

---

## 🧩 Features

- ⚙️ **One-Command Installer** – Installs ErsatzTV directly from the latest GitHub release.
- 👤 **Dedicated System User** – Runs safely under its own `ersatztv` account.
- 📂 **Persistent Data Folder** – Stores all settings and database files in `/home/ersatztv/.local/share/ersatztv`.
- 🧠 **Architecture Detection** – Automatically installs the correct `x64` or `ARM64` binary.
- 🔁 **Hardened Updater** – Includes rollback protection, graceful shutdown, and lock-file safety.
- 🔒 **Data-Safe Updates** – Leaves your database and configuration untouched during upgrades.
- 🚀 **Systemd Integration** – Creates and enables the service automatically for seamless boot startup.
- 🧱 **Fedora/RHEL Compatibility** – Detects Fedora or RHEL systems, installs required packages (`curl`, `tar`, `git`), and automatically adjusts SELinux file contexts.
- 💠 **Ubuntu/Debian Compatibility** – Works seamlessly with Debian-based distributions using built-in `apt`, and supports systems with or without `ufw`.
- 🔥 **Automatic Firewall Configuration** – Opens port `8409/tcp` during installation and removes it on uninstall for both `firewalld` and `ufw` systems.
- 🏷️ **Version / Tag Selection** – Choose exactly which ErsatzTV release to install or downgrade to, including an optional non-interactive `ERSATZTV_VERSION` environment variable.

---

## 🏷️ Version / Tag Selection

By default the installer downloads the latest **develop** build — the safest and most up-to-date option.  
During install or update you will be shown an interactive menu:

```
📦 Select which ErsatzTV version to install:
   1) develop  — latest development build  [DEFAULT, recommended]
   2) latest   — latest stable GitHub release
   3) 26.4     — release 26.4  ⚠️  known WebUI/playout bug
   4) 26.3     — release 26.3  (stable)
   5) custom   — enter any GitHub release tag manually
```

> ⚠️ **26.4 has a known WebUI/playout creation bug.** Use `26.3` or `develop` instead.

### Non-interactive / scripted installs

Set the `ERSATZTV_VERSION` environment variable to bypass the prompt entirely:

**Install the latest develop build (default)**
```bash
curl -sSL https://raw.githubusercontent.com/thehack904/ErsatzTV-Linux-Automation/main/install_linux_ersatztv.sh | sudo bash -s install
```

**Install a specific version (26.3)**
```bash
ERSATZTV_VERSION=26.3 sudo -E bash install_linux_ersatztv.sh install
```

**Downgrade from 26.4 → 26.3** (config and data are preserved)
```bash
ERSATZTV_VERSION=26.3 sudo -E bash install_linux_ersatztv.sh update
```

**Install using a custom / arbitrary tag**
```bash
ERSATZTV_VERSION=v0.8.0 sudo -E bash install_linux_ersatztv.sh install
```

The installer records the installed tag in `/opt/ersatztv/.installed_tag`.  
On subsequent runs the currently-installed tag is displayed before the selection prompt so you always know what version is live.

---

## 🚀 Quick Install (One-Liner)

To install ErsatzTV automatically on any supported Linux system, run:

```bash
curl -sSL https://raw.githubusercontent.com/thehack904/ErsatzTV-Linux-Automation/main/install_linux_ersatztv.sh | sudo bash -s install
```

Manual Download / Execute:
```bash
wget https://raw.githubusercontent.com/thehack904/ErsatzTV-Linux-Automation/main/install_linux_ersatztv.sh
sudo bash install_linux_ersatztv.sh install
```

When complete:
- ErsatzTV will be installed to `/opt/ersatztv`
- Downloads latest ErsatzTV compatible FFmpeg
- It will run as the `ersatztv` user
- Automatically configures firewall (if active)
- Web interface available at:  http://<server-ip>:8409
  
Optional (add RetroIPTVGuide):
```bash
curl -sSL https://raw.githubusercontent.com/thehack904/ErsatzTV-Linux-Automation/main/install_linux_ersatztv.sh | sudo bash -s install --retroiptvguide
```
When complete:
- [RetroIPTVGuide](https://github.com/thehack904/RetroIPTVGuide) will be installed

---

## 🔁 Updating ErsatzTV

Run the included updater script anytime:

(One-Liner)
```bash
curl -sSL https://raw.githubusercontent.com/thehack904/ErsatzTV-Linux-Automation/main/install_linux_ersatztv.sh | sudo bash -s update
```
Manual
```bash
  sudo update_linux_ersatztv.sh
```

**Updater Features**
- Gracefully stops the systemd service  
- Disables auto-restart during update  
- Detects and installs the correct latest build  
- Automatically restarts and verifies the web interface  
- Rolls back automatically if an update fails  

---
## 🧨 Automated Uninstalling ErsatzTV

Run the included updater script anytime:  
This will remove binaries and service but ask if you want to keep `/home/ersatztv` which has the current settings and database if you want a new install at a later date.

Partial Uninstall (Save user data/configs)
```bash
  sudo install_linux_ersatztv.sh uninstall
```

Full Uninstall (Nothing Saved)

One-Liner
```bash
curl -sSL https://raw.githubusercontent.com/thehack904/ErsatzTV-Linux-Automation/main/install_linux_ersatztv.sh | sudo bash -s uninstall --purge
```

Local
```bash
  sudo install_linux_ersatztv.sh uninstall --purge
```

Optional (remove RetroIPTVGuide):
```bash
curl -sSL https://raw.githubusercontent.com/thehack904/ErsatzTV-Linux-Automation/main/install_linux_ersatztv.sh | sudo bash -s uninstall --purge --retroiptvguide
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
- **ErsatzTV** developed by [Jason G. Dove](https://github.com/ErsatzTV/ErsatzTV)
- **RetroIPTVGuide** developed by [thehack904](https://github.com/thehack904/RetroIPTVGuide)

---
