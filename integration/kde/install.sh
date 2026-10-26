#!/bin/sh
# Installs the KDE Plasma 6 (Wayland) integration for the current user:
#  - KWin script that centres the menu under the cursor
#  - Dolphin right-click action "Convert with Clementine"
# Usage: integration/kde/install.sh [path/to/clementine]   (default: ./target/release or debug build)
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
bin=${1:-}
[ -z "$bin" ] && for c in "$root/target/release/clementine" "$root/target/debug/clementine"; do [ -x "$c" ] && bin=$c && break; done
[ -x "$bin" ] || { echo "clementine binary not found, build it or pass its path" >&2; exit 1; }
bin=$(readlink -f "$bin")

kpackagetool6 --type=KWin/Script -r clementine-placer >/dev/null 2>&1 || true
kpackagetool6 --type=KWin/Script -i "$here/kwin-script"
kwriteconfig6 --file kwinrc --group Plugins --key clementine-placerEnabled true
qdbus6 org.kde.KWin /KWin reconfigure

dir=${XDG_DATA_HOME:-$HOME/.local/share}/kio/servicemenus
mkdir -p "$dir"
sed "s|@BIN@|$bin|" "$here/clementine.desktop" > "$dir/clementine.desktop"
chmod +x "$dir/clementine.desktop"
echo "Installed. Right-click a file in Dolphin -> Convert with Clementine."
