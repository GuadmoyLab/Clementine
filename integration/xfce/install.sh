#!/bin/sh
# Adds "Convert with Clementine" to Thunar's custom actions.
set -eu
bin=${1:?usage: integration/xfce/install.sh /path/to/clementine}
[ -x "$bin" ] || { echo "clementine binary not found: $bin" >&2; exit 1; }
bin=$(readlink -f "$bin")
cfg=${XDG_CONFIG_HOME:-$HOME/.config}/Thunar/uca.xml
mkdir -p "$(dirname "$cfg")"
command -v python3 >/dev/null 2>&1 || { echo "python3 is needed to install the Thunar action" >&2; exit 1; }

python3 - "$cfg" "$bin" <<'PY'
import os
import sys
import xml.etree.ElementTree as ET

path, binary = sys.argv[1:]
try:
    root = ET.parse(path).getroot()
except (FileNotFoundError, ET.ParseError):
    root = ET.Element("actions")

for action in list(root.findall("action")):
    command = action.findtext("command", "")
    if "clementine" in command and "--menu" in command:
        root.remove(action)

action = ET.SubElement(root, "action")
for tag, value in (
    ("icon", "view-refresh"),
    ("name", "Convert with Clementine"),
    ("unique-id", "clementine-quick-wheel"),
    ("command", f'{binary} --menu %F'),
    ("description", "Open Clementine's quick conversion wheel"),
    ("patterns", "*"),
    ("directories", ""),
    ("audio-files", ""),
    ("image-files", ""),
    ("other-files", ""),
    ("text-files", ""),
    ("video-files", ""),
):
    ET.SubElement(action, tag).text = value

if hasattr(ET, "indent"):
    ET.indent(root, space="  ")
ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)
PY

echo "Installed Thunar action. Restart Thunar if its context menu is already open."
