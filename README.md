# Clementine

**File converter, right where you drag.** A radial menu pops up under the cursor; pick a format and the file is converted next to the original. Everything runs locally: no uploads, no cloud.

*[Русская версия → README.ru.md](README.ru.md)*

Rust core + Qt 6 / QML interface (via [cxx-qt](https://github.com/KDAB/cxx-qt)). Linux (X11, Wayland) and Windows.

> **Status: working prototype.** The conversion core is covered by tests. The Windows port and the X11 Shift-drag trigger are written but not yet tested on real machines. See [Platform support](#platform-support).

## What it does

The menu adapts to the file you point at. The sectors and lists below are what you see for each kind:

| File | Convert to | Also |
|---|---|---|
| Image | JPG, PNG, WebP, AVIF, HEIC, BMP, TIFF | To PDF, resize (75 / 50 / 25 %, width 1920 / 1280 / 800 px) |
| Video | MP4, MKV, WebM, MOV, AVI, GIF | Still frame (PNG/JPG/WebP), extract audio, **trim**, **split into several named clips at once** |
| Audio | MP3, FLAC, WAV, M4A, OGG, AAC, OPUS | |
| PDF | Images (JPG/PNG), text | Split, compress |
| Document / sheet / slides | PDF, DOCX, DOC, TXT, RTF, ODT, HTML, EPUB, XLSX, CSV, ODS, PPTX, ODP … | |
| Archive | ZIP, 7Z, TAR, TAR.GZ, TAR.XZ | Extract here |
| Any file | | Copy file / path / name, duplicate, SHA-256, create archive |

- **Batch:** select several files and the action is applied to all of them; one progress bar, one summary.
- **Split into clips** (video → *More*): fill in up to 8 rows of *from – to – name* and all clips are cut in one go, next to the original (or in your output folder). Times: `90`, `1:30`, `0:01:30.5`; empty *to* = until the end; empty name = `film-clip2`. All rows are checked before anything is written.
- **Background work with progress and cancel** (✕ or Esc). FFmpeg jobs show real percentages.
- **Settings** (gear button): output folder, keep-both / overwrite, image quality, office suite (LibreOffice / OnlyOffice / auto), language. Stored as TOML in `~/.config/clementine/config.toml` (`%APPDATA%\Clementine\config.toml` on Windows).
- **Language:** English and Russian, follows the system locale unless overridden in settings.
- **Office documents** use LibreOffice (`soffice`) and/or OnlyOffice's `x2t`, whichever is installed.

## Platform support

| Platform | How the menu starts | Tested |
|---|---|---|
| **KDE Plasma 6 (Wayland)** | Dolphin right-click → *Convert with Clementine*; global hotkey **Meta+Shift+C** (uses files copied in Dolphin, or opens empty to drop a file on); `clementine <files>` | Yes, on Plasma 6.7 |
| **Linux X11** | Hold **Shift** and drag a file: the menu appears under the cursor and you drop onto it. Run `clementine` with no arguments (background mode). Also `clementine --menu` | Starts and polls the pointer; real drag not yet tested |
| **Windows 10/11** | Same Shift-drag trigger; Explorer right-click action | Code written, **not compiled or run yet** |
| GNOME and other Wayland | `clementine <files>` only | Works as a normal window; no desktop integration yet |

Why not Shift-drag on Wayland: compositors deliberately do not let applications track the pointer or intercept drags globally. On KDE, a small KWin script places the window under the cursor and the hotkey / Dolphin action start it.

## Requirements

Build: Rust (stable), Qt 6 with QML/Quick development files (`qmake6` in `PATH`), a C++ compiler.
On Windows: the MSVC toolchain, Qt 6 for MSVC, Visual Studio Build Tools.

Runtime tools (each conversion type needs its own; missing ones give a clear error, the rest keeps working):

| Used for | Tool |
|---|---|
| Images | ImageMagick (`magick`) |
| Audio / video | FFmpeg (`ffmpeg`, `ffprobe`) |
| PDF | Poppler (`pdftoppm`, `pdftotext`, `pdfseparate`), Ghostscript (`gs`) |
| Archives | `bsdtar` (libarchive; `tar` on Windows 10+) |
| Office documents | LibreOffice **or** OnlyOffice Desktop Editors |
| Copy file to clipboard / hotkey with clipboard files (Linux) | `wl-clipboard` (Wayland) or `xclip` (X11) |

Arch Linux example:

```bash
sudo pacman -S rust qt6-base qt6-declarative imagemagick ffmpeg poppler ghostscript libarchive wl-clipboard
```

## Build and install

```bash
./build.sh            # release binary: target/release/clementine
./install.sh          # install to ~/.local (binary, launcher, icon, KDE integration on KDE)
./install.sh --uninstall
```

`PREFIX=/usr/local sudo -E ./install.sh` installs system-wide (without the per-user KDE integration).

On KDE the installer also adds the KWin placement script, the Dolphin action and the **Meta+Shift+C** hotkey (change it in *System Settings → Shortcuts → Clementine*). To (re)install only the KDE part: `integration/kde/install.sh [path/to/clementine]`.

### AppImage (Linux x86_64)

```bash
packaging/appimage/build.sh     # -> dist/Clementine-<version>-x86_64.AppImage
```

The first run downloads [linuxdeploy](https://github.com/linuxdeploy/linuxdeploy) and its Qt plugin into `packaging/appimage/.tools` (needs `curl` and network). The image bundles Qt and runs on X11 and Wayland. The converters (FFmpeg, ImageMagick, …) are **not** bundled: they are taken from the host system, so install them as listed in [Requirements](#requirements). For the KDE integration pass the AppImage path: `integration/kde/install.sh path/to/Clementine-*.AppImage`.

Windows (PowerShell): `.\build.ps1` builds and bundles Qt into `dist\Clementine`; `.\install.ps1` installs per user with a Start-menu shortcut and an Explorer right-click action (`-Uninstall` removes it).

Run without installing:

```bash
cargo run --release -- /path/to/file.png
```

## Using it

1. Point at a file (see [Platform support](#platform-support) for how the menu starts on your system).
2. Hover a sector: its list opens on the side nearest to it.
3. Click a format or action. The result appears next to the original (or in your output folder), named `name-2.ext` if the name is taken.
4. Esc or a click outside closes the menu; Esc during a job cancels it.

## Project layout

```
src/convert.rs     conversion core: formats, FFmpeg progress/cancel, office backends, actions (no UI)
src/settings.rs    TOML settings
src/bridge.rs      Rust ↔ QML bridge (background job thread, signals, UI-language messages)
src/trigger.rs     global pointer state for Shift-drag (X11 / Windows)
qml/Main.qml       radial menu, lists, forms, animations
integration/kde/   KWin placement script, Dolphin action, installer
build.sh install.sh build.ps1 install.ps1
packaging/appimage/ AppImage build script and desktop file
```

The converter is independent of the interface, so platform integrations can change without touching conversion code.

```bash
cargo test    # needs magick, ffmpeg, pdftoppm, gs, bsdtar
```

## Known limitations

- Merge PDFs and PDF → DOCX are not implemented yet (shown dimmed in the menu).
- File type is detected by extension, not by content.
- The "fast" trim cuts on keyframes (start may shift by a second or two); "precise" re-encodes.
- PDF/HTML/DOC output from OnlyOffice's `x2t` is limited; install LibreOffice for the full set.
- AppImage is available for x86_64 only (build it yourself, no prebuilt releases yet); no Flatpak / MSI packages yet.

## License

[MIT](LICENSE)
