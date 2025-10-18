# ErsatzTV-Linux-Automation

![Version](https://img.shields.io/badge/version-v1.2.0-blue?style=for-the-badge)
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
  sudo install_linux_ersatztv.sh update
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
For details, see the [CHANGELOG](CHANGELOG.md).

## 🪪 License

This project is licensed under the **zLib License**, allowing free use, modification, and redistribution — including for commercial purposes — provided attribution and license text are retained.

---

## 💬 Credits

- **ErsatzTV-Linux-Automation** maintained by *thehack904*  
- **ErsatzTV** developed by [Jason G. Dove](https://github.com/ErsatzTV/ErsatzTV)
- **RetroIPTVGuide** developed by [thehack904](https://github.com/thehack904/RetroIPTVGuide)

---
