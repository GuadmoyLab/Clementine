#!/bin/sh
# Appends the matching quick-wheel binding and floating rule to a tiling WM config.
set -eu
wm=${1:?usage: integration/tiling/install.sh i3|sway|hyprland [path/to/clementine]}
bin=${2:-$(cd "$(dirname "$0")/../.." && pwd)/target/release/clementine}
[ -x "$bin" ] || { echo "clementine binary not found: $bin" >&2; exit 1; }
bin=$(readlink -f "$bin")
here=$(cd "$(dirname "$0")" && pwd)

case "$wm" in
    i3) cfg=${XDG_CONFIG_HOME:-$HOME/.config}/i3/config ;;
    sway) cfg=${XDG_CONFIG_HOME:-$HOME/.config}/sway/config ;;
    hyprland) cfg=${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.conf ;;
    *) echo "choose i3, sway or hyprland" >&2; exit 1 ;;
esac
mkdir -p "$(dirname "$cfg")"
touch "$cfg"
grep -Fq "Clementine quick wheel" "$cfg" || {
    printf '\n' >> "$cfg"
    sed "s|@BIN@|$bin|g" "$here/$wm.conf" >> "$cfg"
}
echo "Added Clementine quick wheel to $cfg. Reload your window-manager configuration."
