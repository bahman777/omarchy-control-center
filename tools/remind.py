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


def from_reminder_file(path):
    """A reminder set by tools/reminder.py: its message file, in this
    plugin's private runtime folder. Read, then removed (Omarchy's list stops
    showing it), and the bar indicator refreshed."""
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    folder = os.path.join(runtime, "control-center", "reminders")
    if not runtime or os.path.dirname(os.path.realpath(path)) != os.path.realpath(folder):
        return None
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd) as f:
            text = f.read(1000).strip()
        os.unlink(path)
    except OSError:
        return None
    import subprocess
    try:
        title = subprocess.run(["omarchy-i18n", "reminder.title"], capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        title = ""
    subprocess.run(["omarchy-shell", "-q", "omarchy.indicators", "refresh"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"title": title or "Reminder", "body": text, "join": "", "app": "Reminders"}


def main():
    import sys
    if len(sys.argv) == 3 and sys.argv[1] == "--reminder-file":
        r = from_reminder_file(sys.argv[2])
        if r is None:
            return 1
    else:
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
                          GLib.Variant("(susssasa{sv}i)", (str(r.get("app", "Calendar")), 0,
                                       "x-office-calendar" if r.get("app", "Calendar") == "Calendar" else "alarm-symbolic",
                                       title, body, actions, hints, 10000)),
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
