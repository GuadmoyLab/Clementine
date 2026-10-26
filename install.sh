#!/bin/sh
# Installs Clementine for the current user (PREFIX=~/.local by default).
#   ./install.sh              build if needed, install, add KDE integration when running KDE
#   ./install.sh --uninstall  remove everything this script installed
#   PREFIX=/usr/local sudo -E ./install.sh   system-wide (no KDE integration; that is per-user)
set -e
cd "$(dirname "$0")"
PREFIX=${PREFIX:-$HOME/.local}
bin=$PREFIX/bin/clementine
desktop=$PREFIX/share/applications/clementine.desktop
icon=$PREFIX/share/icons/hicolor/scalable/apps/clementine.svg
kde_menu=${XDG_DATA_HOME:-$HOME/.local/share}/kio/servicemenus/clementine.desktop

if [ "$1" = "--uninstall" ]; then
    rm -f "$bin" "$desktop" "$icon"
    # the KDE integration is per-user and only installed for PREFIX=~/.local
    if [ "$PREFIX" = "$HOME/.local" ] && command -v kpackagetool6 >/dev/null 2>&1; then
        rm -f "$kde_menu"
        kpackagetool6 --type=KWin/Script -r clementine-placer >/dev/null 2>&1 || true
        kwriteconfig6 --file kwinrc --group Plugins --key clementine-placerEnabled false
        qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    fi
    echo "Uninstalled from $PREFIX"
    exit 0
fi

[ -x target/release/clementine ] || ./build.sh

install -Dm755 target/release/clementine "$bin"
install -Dm644 integration/clementine.svg "$icon"
mkdir -p "$(dirname "$desktop")"
cat > "$desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Clementine
Comment=File converter, right where you drag
Exec=$bin --app %F
Icon=clementine
Terminal=false
Categories=Utility;
Actions=Menu;

# Global hotkey on KDE (kglobalaccel reads X-KDE-Shortcuts; change it in System Settings > Shortcuts)
[Desktop Action Menu]
Name=Open menu at cursor
Exec=$bin --menu
X-KDE-Shortcuts=Meta+Shift+C
DESK
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$(dirname "$desktop")" 2>/dev/null || true

case "$XDG_CURRENT_DESKTOP" in
    *KDE*) [ "$PREFIX" = "$HOME/.local" ] && integration/kde/install.sh "$bin" ;;
esac

if [ "$PREFIX" = "$HOME/.local" ] && command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 >/dev/null 2>&1 || true
    # kglobalaccel only picks up new desktop-file shortcuts on start
    systemctl --user restart plasma-kglobalaccel.service >/dev/null 2>&1 || true
fi

echo "Installed to $PREFIX (binary: $bin)"
case ":$PATH:" in *":$PREFIX/bin:"*) ;; *) echo "note: $PREFIX/bin is not in PATH" >&2 ;; esac
