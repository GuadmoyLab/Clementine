from gi.repository import GObject, Nautilus
from urllib.parse import unquote
import subprocess


class ClementineExtension(GObject.GObject, Nautilus.MenuProvider):
    """Adds the radial Clementine menu to Nautilus' file context menu."""

    def get_file_items(self, files):
        if not files:
            return []
        item = Nautilus.MenuItem(
            name="Clementine::convert",
            label="Convert with Clementine",
            tip="Open the Clementine quick wheel for these files",
        )
        item.connect("activate", self._convert, files)
        return [item]

    def _convert(self, _item, files):
        paths = [unquote(file.get_uri()[7:]) for file in files if file.get_uri().startswith("file://")]
        if paths:
            subprocess.Popen(["@BIN@", "--menu", *paths])
