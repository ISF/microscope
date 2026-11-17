# Changelog

All notable changes to Microscope are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- The live preview and saved images are never mirrored. Mirroring is now
  explicitly disabled instead of left to macOS, which can mirror the preview
  automatically depending on the camera.

## [0.1.1] - 2026-11-17

### Fixed
- Removed the stray flower symbol (SF Symbol `camera.macro`) next to the
  camera picker; its tooltip now sits on the picker itself.

### Changed
- `./build.sh install` installs to `/Applications` instead of
  `~/Applications`.
- Release notes are now taken from this changelog.

## [0.1] - 2026-11-17

First release.

### Added
- Live preview from any UVC camera, opening the USB microscope
  (`GENERAL - UVC`, `1B3F:2002`) automatically and re-attaching on re-plug.
- Full-resolution snapshots (Space / ⌘S) as PNG or JPEG, timestamped, saved
  to `~/Pictures/Microscope` by default; ⌘C copies the frame, ⌘R reveals
  saved images.
- Camera picker in the bottom bar and a Camera menu (⌘1…⌘9), plus a default
  camera setting.
- Resolution picker defaulting to the largest mode; the status bar shows the
  actual frame size. The device configuration lock is held while in use so
  macOS doesn't silently fall back to 1080p.
- Settings window (⌘,): save folder, file format, default camera.
- Procedurally drawn app icon.
- Signed release tooling (`scripts/release.sh`).

[0.1.1]: https://github.com/ISF/microscope/releases/tag/v0.1.1
[0.1]: https://github.com/ISF/microscope/releases/tag/v0.1
