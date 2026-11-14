#!/usr/bin/env python3
"""Set a reminder with custom text, without the text on any command line.

    reminder.py set <minutes>      (the message comes on stdin)

Makes the same kind of reminder `omarchy-reminder <minutes> <message>` does,
so Omarchy's `omarchy-reminder show`/`clear` and the bar indicator see it:
a user timer named omarchy-reminder-<minutes>m-<epoch> and the message in
$XDG_RUNTIME_DIR/omarchy-reminders/<unit>.message. Unlike omarchy-reminder,
the message is never passed to systemd-run: the timer runs tools/remind.py
with the message file's path, which reads it, sends the notification over
D-Bus and removes the file.
"""
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def main(argv):
    if len(argv) != 3 or argv[1] != "set" or not argv[2].isdigit():
        print("usage: reminder.py set <minutes>  (message on stdin)", file=sys.stderr)
        return 2
    minutes = int(argv[2])
    if not 1 <= minutes <= 10080:
        return 2
    message = " ".join(sys.stdin.read(4096).split())[:200]
    if not message:
        return 2

    runtime = os.environ.get("XDG_RUNTIME_DIR") or ""
    if not runtime or not os.path.isdir(runtime):
        print("no XDG_RUNTIME_DIR", file=sys.stderr)
        return 1
    folder = os.path.join(runtime, "omarchy-reminders")
    os.makedirs(folder, mode=0o700, exist_ok=True)
    unit = "omarchy-reminder-%dm-%d" % (minutes, int(time.time()))
    path = os.path.join(folder, unit + ".message")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(message)

    r = subprocess.run(["systemd-run", "--user", "--quiet", "--collect", "--on-active=%dm" % minutes,
                        "--unit=" + unit, "python3", "-I", os.path.join(HERE, "remind.py"), "--reminder-file", path])
    if r.returncode != 0:
        os.unlink(path)
        return 1
    subprocess.run(["omarchy-shell", "-q", "omarchy.indicators", "refresh"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
