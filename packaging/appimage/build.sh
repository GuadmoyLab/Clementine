#!/bin/sh
# Builds dist/Clementine-<version>-x86_64.AppImage with linuxdeploy + its Qt plugin.
# The tools are downloaded once into packaging/appimage/.tools (official linuxdeploy releases on GitHub).
# Converters (ffmpeg, magick, ...) are NOT bundled: they come from the host system, see README.
set -e
cd "$(dirname "$0")/../.."
root=$PWD
tools=$root/packaging/appimage/.tools
arch=x86_64
[ "$(uname -m)" = "$arch" ] || { echo "only $arch is supported by this script" >&2; exit 1; }
command -v qmake6 >/dev/null 2>&1 || { echo "qmake6 not found" >&2; exit 1; }

./build.sh

mkdir -p "$tools"
fetch() { # name url
    [ -x "$tools/$1" ] || { echo "downloading $1"; curl -fsSL --retry 3 -o "$tools/$1" "$2"; chmod +x "$tools/$1"; }
}
fetch linuxdeploy-$arch.AppImage "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$arch.AppImage"
fetch linuxdeploy-plugin-qt-$arch.AppImage "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-$arch.AppImage"

version=$(sed -n 's/^version *= *"\(.*\)"/\1/p' Cargo.toml | head -1)
appdir=$root/target/appimage/AppDir
rm -rf "$appdir"

export PATH="$tools:$PATH"
export APPIMAGE_EXTRACT_AND_RUN=1          # no FUSE needed to run the tools
real_qmake=$(command -v qmake6)
# The UI needs no image-format plugins, and distro extras (kimg_*) drag in libraries that may be missing.
# So the Qt plugin is shown only the plugin folders we want, through a qmake wrapper.
plugins=$root/target/appimage/qt-plugins
rm -rf "$plugins"; mkdir -p "$plugins"
qtplugins=$("$real_qmake" -query QT_INSTALL_PLUGINS)
for d in platforms platforminputcontexts xcbglintegrations wayland-shell-integration wayland-decoration-client; do
    [ -d "$qtplugins/$d" ] && ln -s "$qtplugins/$d" "$plugins/$d"
done
cat > "$root/target/appimage/qmake" <<WRAP
#!/bin/sh
exec "$real_qmake" "\$@" | sed "s|^QT_INSTALL_PLUGINS:.*|QT_INSTALL_PLUGINS:$plugins|"
WRAP
chmod +x "$root/target/appimage/qmake"
export QMAKE=$root/target/appimage/qmake
export QML_SOURCES_PATHS=$root/qml         # the plugin deploys the QML modules Main.qml imports
# Wayland platform plugin: one file in Qt >= 6.8 (libqwayland.so), generic + egl before that
plat=$qtplugins/platforms
wl=
for f in libqwayland.so libqwayland-generic.so libqwayland-egl.so; do [ -e "$plat/$f" ] && wl="$wl${wl:+;}$f"; done
export EXTRA_PLATFORM_PLUGINS=$wl
export NO_STRIP=1                             # linuxdeploy's bundled strip chokes on .relr.dyn sections of current distros
export LINUXDEPLOY_OUTPUT_VERSION=$version

mkdir -p dist target/appimage
cd target/appimage
# Pass 1: binary, libraries, Qt platform plugins and QML modules
linuxdeploy-$arch.AppImage --appdir "$appdir" \
    --executable "$root/target/release/clementine" \
    --desktop-file "$root/packaging/appimage/clementine.desktop" \
    --icon-file "$root/integration/clementine.svg" \
    --plugin qt

# The Qt plugin does not know the Wayland EGL client plugin: without it the Wayland window cannot be created.
gfx=wayland-graphics-integration-client
mkdir -p "$appdir/usr/plugins/$gfx"
cp "$qtplugins/$gfx/libqt-plugin-wayland-egl.so" "$appdir/usr/plugins/$gfx/"

# The plugin copies whole Qt module trees; keep only what Main.qml imports (QtQuick, .Window, .Shapes)
# and drop Qt's own translations (the app has its own).
for d in "$appdir"/usr/qml/QtQuick/*/; do
    case $(basename "$d") in Window|Shapes) ;; *) rm -rf "$d" ;; esac
done
rm -rf "$appdir/usr/translations"

# Pass 2: its dependencies, then the image
linuxdeploy-$arch.AppImage --appdir "$appdir" --deploy-deps-only "$appdir/usr/plugins/$gfx" --output appimage

mv Clementine-*.AppImage "$root/dist/"
echo "Built: $(ls "$root"/dist/Clementine-*.AppImage)"
