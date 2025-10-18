# Changelog

## v1.2.0 - 2025-10-18
- Added automatic Fedora/RHEL compatibility detection and prerequisite installation
- Implemented SELinux enforcement detection and context repair for /opt/ersatztv and /home/ersatztv
- Added dynamic nologin path detection for cross-distro user creation
- Introduced automatic firewall configuration for firewalld and ufw (opens port 8409 on install, removes on uninstall)
- Displayed accessible server IP and URL upon install completion
- Incremented installer version to v1.2.0

## v1.1.0 - 2025-10-12
- Added --version flag to installer
- Added version badges to README
- Finalized FFmpeg path detection and ownership patches
- Corrected /opt permissions and automatic fixes

## v1.0.0 - 2025-10-11
- Initial release: automated installer and updater for ErsatzTV.
