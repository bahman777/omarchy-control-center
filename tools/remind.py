#!/usr/bin/env python3
"""Send a meeting reminder; with a Join button when the event has a link.

The reminder (title, details, meeting link) comes in the CC_REMINDER
environment variable as JSON, which only this account can read, instead of
on a command line (notify-send's), which every local account can see.
Sends over D-Bus (org.freedesktop.Notifications), waits up to an hour for a
click, and opens the meeting link if Join is pressed.
"""
import json
import os

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402


def main():
    try:
        r = json.loads(os.environ.pop("CC_REMINDER", "{}"))
    except ValueError:
        return 1
    title = str(r.get("title", ""))[:300]
    body = str(r.get("body", ""))[:1000]
    join = str(r.get("join", ""))
    if not join.startswith("https://"):
        join = ""

    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    actions = ["join", "Join"] if join else []
    hints = {"urgency": GLib.Variant("y", 1)}
    reply = bus.call_sync("org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                          "org.freedesktop.Notifications", "Notify",
                          GLib.Variant("(susssasa{sv}i)", ("Calendar", 0, "x-office-calendar", title, body, actions, hints, 10000)),
                          GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, 5000, None)
    nid = reply.unpack()[0]
    if not join:
        return 0

    loop = GLib.MainLoop()

    def on_signal(_conn, _sender, _path, _iface, signal, params):
        args = params.unpack()
        if args[0] != nid:
            return
        if signal == "ActionInvoked" and args[1] == "join":
            Gio.AppInfo.launch_default_for_uri(join, None)
        loop.quit()

    for sig in ("ActionInvoked", "NotificationClosed"):
        bus.signal_subscribe("org.freedesktop.Notifications", "org.freedesktop.Notifications", sig,
                             "/org/freedesktop/Notifications", None, Gio.DBusSignalFlags.NONE, on_signal)
    GLib.timeout_add_seconds(3600, loop.quit)
    loop.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
