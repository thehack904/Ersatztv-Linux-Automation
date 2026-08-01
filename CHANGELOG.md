# Changelog

## Unreleased

## v1.3.0 - 2026-08-01

### Added
- Added the canonical `ersatztv-linux-automation.sh` lifecycle script and installed management command at `/usr/local/sbin/ersatztv-linux-automation`.
- Added explicit lifecycle actions: `--install`, `--upgrade`, `--repair`, `--uninstall`, `--version`, and `--help`.
- Added strict action validation, including rejection of missing, conflicting, unsupported, and unknown arguments.
- Added compatibility wrappers at `/usr/local/bin/install_linux_ersatztv.sh` and `/usr/local/bin/update_linux_ersatztv.sh`.
- Added release-driven managed FFmpeg requirement resolution from selected ErsatzTV Legacy release notes and assets.
- Added compatibility detection precedence: release-note link, release-note text, release asset, known mapping, and inherited fallback.
- Added built-in compatibility mappings for `v26.7.0 -> 8.1.2` and `v25.2.0 -> 7.1.1`.
- Added compatibility caching under `/var/lib/ersatztv-linux-automation/compatibility/`.
- Added direct release-asset resolution for `ErsatzTV/ErsatzTV-ffmpeg`, including `n8.1.2` filename matching and newest-compatible-asset selection.
- Added post-start verification of the FFmpeg and FFprobe paths reported by ErsatzTV, with exact Web UI correction instructions when a mismatch is detected.
- Added Back and Cancel choices to interactive version selection so users can return to the prior menu or exit before changes begin.
- Added regression coverage for CLI validation, wrappers, FFmpeg resolution and upgrade decisions, lock handling, menus, health notices, and required function definitions.

### Changed
- Renamed the canonical project script from `install_linux_ersatztv.sh` to `ersatztv-linux-automation.sh`.
- Updated one-line commands to use `bash -s --` and explicit long-form actions.
- Kept transitional positional compatibility for `install`, `update`, and `uninstall`, with deprecation warnings.
- Limited the interactive release menu to `develop`, `latest`, and `custom`.
- Changed the custom release menu to show only the current published ErsatzTV Legacy release and the three immediately preceding releases.
- Removed manual arbitrary-tag entry from the interactive flow; exact tags remain available through `ERSATZTV_VERSION`.
- Expanded user-facing documentation to state that the project supports ErsatzTV Legacy only and does not support or migrate ErsatzTV Next.
- Updated architecture handling to explicitly support `x86_64`/`amd64` and `aarch64`/`arm64`; unsupported architectures now fail early.
- Upgrades managed FFmpeg only when required by the selected ErsatzTV release or when the existing managed binaries are missing or invalid.

### Fixed
- Restored the `create_user_and_dirs` function accidentally removed while adding Back/Cancel menu navigation. Its absence caused `--install`, `--upgrade`, and `--repair` to fail with `create_user_and_dirs: command not found`.
- Fixed FFmpeg requirement resolution so diagnostic output cannot contaminate version comparisons or asset URLs, and resolved release metadata persists outside the resolver.
- Fixed numeric FFmpeg version comparison so versions such as `8.10.0` correctly compare as newer than `8.2.0`.
- Fixed managed FFmpeg archive handling to accept both `ffmpeg/ffmpeg` and `ffmpeg/bin/ffmpeg` layouts.
- Fixed managed FFmpeg runtime-path detection so the service only receives a directory containing executable `ffmpeg` and `ffprobe` files.
- Fixed managed-bundle validation to inspect the actual `ffmpeg` and `ffprobe` executables instead of trusting only `.installed_ffmpeg_version`.
- Fixed transactional upgrades to empty the ErsatzTV application directory as required by the official Linux update procedure while preserving a separately managed, validated FFmpeg bundle when replacement is unnecessary.
- Fixed asset lookup failures so `set -e` does not silently terminate an upgrade; available assets and a specific error are now displayed.
- Added safe abort and rollback behavior when no supported managed FFmpeg layout exists after installation.
- Fixed the repository-level deprecated installer so old `curl .../install_linux_ersatztv.sh | sudo bash` commands bootstrap the canonical script instead of requiring an adjacent local file.

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
- Implemented SELinux enforcement detection and context repair for `/opt/ersatztv` and `/home/ersatztv`
- Added dynamic nologin path detection for cross-distro user creation
- Introduced automatic firewall configuration for firewalld and ufw (opens port 8409 on install, removes on uninstall)
- Displayed accessible server IP and URL upon install completion
- Incremented installer version to v1.2.0

## v1.1.0 - 2025-10-12
- Added `--version` flag to installer
- Added version badges to README
- Finalized FFmpeg path detection and ownership patches
- Corrected `/opt` permissions and automatic fixes

## v1.0.0 - 2025-10-11
- Initial release: automated installer and updater for ErsatzTV.
