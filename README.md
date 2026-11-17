<img src="Resources/icon-source.png" width="128" alt="Microscope icon" align="right">

# Microscope

A tiny native macOS app for USB microscopes (and any other UVC camera): live
view, one-key full-resolution snapshots, nothing else.

Built for a generic "4K WiFi USB" digital microscope that enumerates as
**`GENERAL - UVC`** (USB `1B3F:2002`), but works with any camera macOS sees.

## Features

- Opens the microscope automatically and re-attaches when it is unplugged and
  plugged back in.
- Pick any connected camera from the bottom bar, the **Camera** menu
  (⌘1…⌘9), or set a default in Settings.
- Resolution picker, defaulting to the camera's largest mode. The status bar
  shows the size of the frames actually arriving.
- **Space** / **⌘S** saves the current frame at full resolution (PNG or
  JPEG) as `microscope_YYYY-MM-DD_HH-mm-ss-SSS.png`.
- **⌘C** copies the current frame, **⌘R** reveals saved images.
- **Settings (⌘,)**: save folder (default `~/Pictures/Microscope`), file
  format, default camera.

## Build

Requires macOS 14+ and the Xcode command-line tools (Swift 5.10+). No Xcode
project needed.

```sh
./build.sh            # -> build/Microscope.app
./build.sh install    # also copies it to ~/Applications
```

The app is ad-hoc signed. macOS asks for camera access on first launch.

The icon is drawn procedurally; edit `scripts/generate_icon.swift` and run
`scripts/make_icon.sh` to regenerate `Resources/AppIcon.icns`.

## Notes on cheap UVC microscopes

- Many advertise 30 fps at every resolution. The unit this was built for
  delivers ~10 fps at 3840×2160 and ~20 fps at 1080p, but its 4K frames do
  contain real detail beyond 1080p, so the app prefers the largest mode.
- macOS capture sessions silently re-apply their default preset (1080p) when
  the session topology changes, e.g. when the preview layer attaches. The app
  holds the device's configuration lock while in use so the chosen resolution
  sticks.

## Headless snapshot

No app needed for a quick grab from the terminal:

```sh
ffmpeg -f avfoundation -framerate 30 -video_size 3840x2160 -i "GENERAL - UVC" \
  -vf "select=gte(n\,30)" -frames:v 1 -update 1 shot.png
```

## License

[MIT](./LICENSE)
