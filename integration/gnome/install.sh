#!/bin/sh
# Installs the Nautilus context action and a GNOME quick-wheel shortcut.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
bin=${1:?usage: integration/gnome/install.sh /path/to/clementine}
[ -x "$bin" ] || { echo "clementine binary not found: $bin" >&2; exit 1; }
bin=$(readlink -f "$bin")
data=${XDG_DATA_HOME:-$HOME/.local/share}
dir=$data/nautilus-python/extensions
mkdir -p "$dir"
sed "s|@BIN@|$bin|g" "$here/clementine.py" > "$dir/clementine.py"

# GNOME stores user-defined shortcuts as a list of schema paths.
if command -v gsettings >/dev/null 2>&1; then
    base=org.gnome.settings-daemon.plugins.media-keys
    path=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/clementine/
    existing=$(gsettings get "$base" custom-keybindings)
    case "$existing" in
        *"$path"*) ;;
        "[]") gsettings set "$base" custom-keybindings "['$path']" ;;
        *) gsettings set "$base" custom-keybindings "${existing%]}, '$path']" ;;
    esac
    key="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$path"
    gsettings set "$key" name "Clementine quick wheel"
    gsettings set "$key" command "$bin --menu"
    gsettings set "$key" binding "<Super><Shift>c"
fi

command -v nautilus >/dev/null 2>&1 && nautilus -q || true
echo "Installed Nautilus action and Super+Shift+C quick wheel. On Wayland, GNOME centres the wheel because it cannot expose the pointer position."
