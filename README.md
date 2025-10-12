# ErsatzTV-Linux-Automation

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

---

## 🚀 Quick Install (One-Liner)

To install ErsatzTV automatically on any supported Linux system, run:

```bash
curl -sSL https://raw.githubusercontent.com/thehack904/ErsatzTV-Linux-Automation/main/install_linux_ersatztv.sh | sudo bash
```

Manual Download / Execute:
```bash
sudo bash install_linux_ersatztv.sh
```

When complete:
- ErsatzTV will be installed to `/opt/ersatztv`
- It will run as the `ersatztv` user
- Web interface available at:  http://<server-ip>:8409

---

## 🔁 Updating ErsatzTV

Run the included updater script anytime:

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

## 🧠 Systemd Service Example

A fully configured service file is automatically created at:
`/etc/systemd/system/ersatztv.service`

```ini
[Unit]
Description=ErsatzTV Service
After=network.target

[Service]
User=ersatztv
WorkingDirectory=/opt/ersatztv
ExecStart=/opt/ersatztv/ErsatzTV --data-folder /home/ersatztv/.local/share/ersatztv
ExecStop=/bin/kill -s SIGINT $MAINPID
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

---

## 📁 Repository Structure

```
ErsatzTV-Linux-Automation/
├── install_linux_ersatztv.sh        # Main installer script
├── README.md                        # Documentation and usage
├── LICENSE                          # zLib License
├── CHANGELOG.md                     # Version history
└── examples/
    └── ersatztv.service.example      # Reference systemd unit
```

---

## 🧹 Future Roadmap

- 🔄 `uninstall_linux_ersatztv.sh` – Safe removal while preserving data  
- 🩺 `healthcheck_ersatztv.sh` – Verify uptime, DB integrity, and port status  
- 🐳 Docker-based CI testing for both Ubuntu and ARM builds  

---

## 🪪 License

This project is licensed under the **zLib License**, allowing free use, modification, and redistribution — including for commercial purposes — provided attribution and license text are retained.

---

## 💬 Credits

- **ErsatzTV-Linux-Automation** maintained by *thehack904*  
- **ErsatzTV** developed by [Jason G. Dove](https://github.com/ErsatzTV/ErsatzTV)

---
