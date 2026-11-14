#!/usr/bin/env python3
"""Reminders with custom text, without the text on any command line.

    reminder.py set <minutes>      (the message comes on stdin)
    reminder.py list               (JSON, like `omarchy-reminder show -j`)
    reminder.py migrate            (move older reminders' text, see below)

A reminder is a user timer named omarchy-reminder-<minutes>m-<epoch>, as
`omarchy-reminder` makes, so Omarchy's count, indicator and `clear` still
work. Its text is kept in this plugin's own private folder,
$XDG_RUNTIME_DIR/control-center/reminders/<unit>.message (0700/0600), not in
Omarchy's: `omarchy-reminder show` passes the text of the files in its own
folder to jq as arguments. The timer runs tools/remind.py with the file's
path, which reads it, removes it and notifies over D-Bus. Listing reads the
timers from systemd and the text from the files, all in-process.

Migration: an earlier version kept the text in Omarchy's folder. Any of our
pending reminders whose text is still there (identified by its service
running our remind.py) has the file moved into our folder; remind.py looks
there first by file name, so it still fires with its text. Runs when the
plugin loads and before every listing. Reminders made by Omarchy itself are
left alone.
"""
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def folder():
    runtime = os.environ.get("XDG_RUNTIME_DIR") or ""
    if not runtime or not os.path.isdir(runtime):
        return ""
    return os.path.join(runtime, "control-center", "reminders")


def read_message(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd) as f:
            return f.read(1000).strip()
    except OSError:
        return ""


OMARCHY = "omarchy-reminders"


def migrate(units=None):
    runtime = os.environ.get("XDG_RUNTIME_DIR") or ""
    theirs, ours = os.path.join(runtime, OMARCHY), folder()
    if not runtime or not ours or not os.path.isdir(theirs):
        return 0
    names = [n for n in os.listdir(theirs) if n.startswith("omarchy-reminder-") and n.endswith(".message")]
    moved = 0
    for name in names:
        unit = name[:-len(".message")]
        if units is not None and unit not in units:
            continue
        r = subprocess.run(["systemctl", "--user", "show", unit + ".service", "-p", "ExecStart", "--value"],
                           capture_output=True, text=True, timeout=10)
        if os.path.join(HERE, "remind.py") not in r.stdout or "--reminder-file" not in r.stdout:
            continue  # not one of ours
        os.makedirs(ours, mode=0o700, exist_ok=True)
        os.chmod(ours, 0o700)
        src, dst = os.path.join(theirs, name), os.path.join(ours, name)
        try:
            os.chmod(src, 0o600)
            os.rename(src, dst)
            moved += 1
        except OSError:
            pass
    return moved


def duration(seconds):
    m, s = divmod(max(0, int(seconds)), 60)
    h, m = divmod(m, 60)
    if h:
        return "%d h %d min" % (h, m) if m else "%d h" % h
    if m:
        return "%d min %d s" % (m, s) if s and m < 5 else "%d min" % m
    return "%d s" % s


def list_reminders():
    out = subprocess.run(["systemctl", "--user", "list-timers", "--all", "--output=json", "omarchy-reminder-*.timer"],
                         capture_output=True, text=True, timeout=10).stdout
    try:
        timers = json.loads(out or "[]")
    except ValueError:
        timers = []
    now = time.time()
    migrate()
    ours = folder()
    items, live = [], set()
    for t in timers:
        timer, nxt = str(t.get("unit", "")), t.get("next")
        if not timer.startswith("omarchy-reminder-") or not nxt:
            continue
        at = int(nxt) / 1e6
        if at <= now:
            continue
        unit = timer[:-len(".timer")]
        live.add(unit)
        mins = unit[len("omarchy-reminder-"):].split("m-", 1)[0]
        mins = int(mins) if mins.isdigit() else 0
        # Ours first; Omarchy's own folder for reminders set elsewhere.
        msg = read_message(os.path.join(ours, unit + ".message")) if ours else ""
        if not msg:
            msg = read_message(os.path.join(os.environ.get("XDG_RUNTIME_DIR", ""), "omarchy-reminders", unit + ".message"))
        items.append({"unit": unit, "timer": timer, "minutes": mins, "message": msg,
                      "label": msg or ("%d minute%s" % (mins, "" if mins == 1 else "s")),
                      "remaining": duration(at - now), "remainingSeconds": int(at - now), "at": int(at),
                      "atTime": time.strftime("%-H:%M", time.localtime(at))})
    # Text of reminders that were cleared or have fired.
    if ours and os.path.isdir(ours):
        for name in os.listdir(ours):
            if name.endswith(".message") and name[:-len(".message")] not in live:
                try:
                    os.unlink(os.path.join(ours, name))
                except OSError:
                    pass
    items.sort(key=lambda r: r["at"])
    print(json.dumps({"count": len(items), "active": bool(items), "reminders": items}))
    return 0


def main(argv):
    if len(argv) == 2 and argv[1] == "list":
        return list_reminders()
    if len(argv) == 2 and argv[1] == "migrate":
        migrate()
        return 0
    if len(argv) != 3 or argv[1] != "set" or not argv[2].isdigit():
        print("usage: reminder.py set <minutes>  (message on stdin)", file=sys.stderr)
        return 2
    minutes = int(argv[2])
    if not 1 <= minutes <= 10080:
        return 2
    message = " ".join(sys.stdin.read(4096).split())[:200]
    if not message:
        return 2

    ours = folder()
    if not ours:
        print("no XDG_RUNTIME_DIR", file=sys.stderr)
        return 1
    os.makedirs(ours, mode=0o700, exist_ok=True)
    os.chmod(ours, 0o700)
    unit = "omarchy-reminder-%dm-%d" % (minutes, int(time.time()))
    path = os.path.join(ours, unit + ".message")
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
