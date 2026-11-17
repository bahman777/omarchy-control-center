#!/usr/bin/env python3
"""Pick a picture (or video) as the wallpaper with the desktop's file dialog.

Opens the standard Open dialog through xdg-desktop-portal (FileChooser), so
there is a real Open button. The chosen file is copied into the current
theme's own backgrounds folder (~/.config/omarchy/backgrounds/<theme>/,
which `omarchy theme bg next` and the Control Center's picker list), unless
it's already there, and set with `omarchy-theme-bg-set`.
"""
import os
import random
import shutil
import subprocess
import sys
from urllib.parse import unquote, urlparse

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

HOME = os.path.expanduser("~")
EXTS = ("jpg", "jpeg", "png", "webp", "mp4", "webm", "mov")


def theme_folder():
    try:
        name = open(os.path.join(HOME, ".local/state/omarchy/current/theme.name")).read().strip()
    except OSError:
        name = ""
    if not name or "/" in name:
        return None
    return os.path.join(HOME, ".config/omarchy/backgrounds", name)


def choose():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    token = "cc_wallpaper_%d" % random.randint(0, 1 << 30)
    sender = bus.get_unique_name()[1:].replace(".", "_")
    handle = "/org/freedesktop/portal/desktop/request/%s/%s" % (sender, token)
    result = {"uris": None}
    loop = GLib.MainLoop()

    def on_response(_c, _s, _p, _i, _sig, params):
        code, res = params.unpack()
        if code == 0:
            result["uris"] = list(res.get("uris", []))
        loop.quit()

    bus.signal_subscribe("org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request", "Response",
                         handle, None, Gio.DBusSignalFlags.NO_MATCH_RULE, on_response)
    patterns = [(0, "*." + e) for e in EXTS] + [(0, "*." + e.upper()) for e in EXTS]
    options = {
        "handle_token": GLib.Variant("s", token),
        "modal": GLib.Variant("b", True),
        "filters": GLib.Variant("a(sa(us))", [("Pictures and videos", patterns)]),
        "current_folder": GLib.Variant("ay", (os.path.join(HOME, "Pictures") + "\0").encode()),
    }
    bus.call_sync("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
                  "org.freedesktop.portal.FileChooser", "OpenFile",
                  GLib.Variant("(ssa{sv})", ("", "Choose a wallpaper", options)),
                  None, Gio.DBusCallFlags.NONE, -1, None)
    GLib.timeout_add_seconds(900, loop.quit)
    loop.run()
    return result["uris"]


def main():
    uris = choose()
    if not uris:
        return 1  # cancelled
    src = unquote(urlparse(uris[0]).path)
    if not os.path.isfile(src) or not src.lower().endswith(EXTS):
        return 2
    folder = theme_folder()
    dest = src
    if folder:
        os.makedirs(folder, exist_ok=True)
        if os.path.realpath(os.path.dirname(src)) != os.path.realpath(folder):
            base, ext = os.path.splitext(os.path.basename(src))
            dest = os.path.join(folder, base + ext)
            n = 2
            while os.path.exists(dest) and not os.path.samefile(dest, src):
                dest = os.path.join(folder, "%s-%d%s" % (base, n, ext))
                n += 1
            if not os.path.exists(dest):
                shutil.copy2(src, dest)
    r = subprocess.run(["omarchy-theme-bg-set", dest])
    print(dest)
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
