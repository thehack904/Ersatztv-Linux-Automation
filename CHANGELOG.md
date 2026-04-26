# Changelog

## v1.2.1 - 2026-04-26
- Added interactive version/tag selection menu during install and update (develop, latest, 26.4, 26.3, custom)
- Added `ERSATZTV_VERSION` environment variable for non-interactive/scripted installs
- Default tag is `develop` (maps to `ghcr.io/ersatztv/legacy:develop`)
- Added warning and 5-second countdown when tag `26.4` is selected (known WebUI/playout creation bug)
- Installer now detects and displays the currently installed tag before prompting for selection
- Installed tag is recorded in `/opt/ersatztv/.installed_tag` for future reference
- Downgrade support: selecting an older tag replaces the binary while preserving all config, database, and media paths
- Validated tag input to reject blank/whitespace-only values
- Updated `show_usage()` and README with version-selection examples
- Bumped installer version to v1.2.1

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
