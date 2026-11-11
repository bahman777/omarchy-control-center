#!/usr/bin/env python3
"""Calendar feeds for Control Center.

  calendar.py events [--refresh]   JSON: calendars + events (prev month … +3 months)
  calendar.py add URL [NAME]       add an iCal (.ics) link, then print events
  calendar.py remove ID            remove a calendar
  calendar.py set ID KEY=VALUE…    name=…, color=#rrggbb, enabled=true|false

Feeds are any .ics link (Google "Secret address in iCal format", iCloud,
Outlook, Fastmail, Nextcloud) or a local .ics path. The list is kept in
~/.local/state/omarchy/control-center/calendars.json (mode 600: the links are
secret). On first use it imports the links Dynamic Island was using. Each
feed is cached, so events still show offline; a feed is fetched again after
15 minutes, or at once with --refresh.
"""
import datetime as dt
import hashlib
import json
import os
import re
import sys
import urllib.request

HOME = os.path.expanduser("~")
STATE = os.path.join(HOME, ".local/state/omarchy/control-center/calendars.json")
CACHE = os.path.join(HOME, ".cache/omarchy-control-center/calendars")
MAX_BYTES = 20 * 1024 * 1024
STALE_SECS = 15 * 60
PALETTE = ["#4f8cf7", "#3fb98f", "#e0688a", "#e8a33d", "#c07ee8", "#47b5c4"]
JOIN_RE = re.compile(r"https://(?:[\w-]+\.)?(?:meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com|webex\.com)/[^\s\"<>\\]+")


def feed_id(url):
    return hashlib.sha1(url.encode()).hexdigest()[:10]


def find_calendars(obj):
    """Every string in any "calendars" list inside shell.json (island settings)."""
    out = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == "calendars" and isinstance(v, list):
                out += [x for x in v if isinstance(x, str)]
            else:
                out += find_calendars(v)
    elif isinstance(obj, list):
        for v in obj:
            out += find_calendars(v)
    return out


def import_island():
    urls = []
    try:
        urls += find_calendars(json.load(open(os.path.join(HOME, ".config/omarchy/shell.json"))))
    except (OSError, ValueError):
        pass
    try:
        added = json.load(open(os.path.join(HOME, ".config/omarchy/dynamic-island/calendars.json")))
        for x in added if isinstance(added, list) else []:
            urls.append(x if isinstance(x, str) else str(x.get("url", "")) if isinstance(x, dict) else "")
    except (OSError, ValueError):
        pass
    seen, feeds = set(), []
    for u in urls:
        u = u.strip()
        if u and u not in seen:
            seen.add(u)
            feeds.append({"id": feed_id(u), "url": u, "name": "", "color": PALETTE[len(feeds) % len(PALETTE)], "enabled": True})
    return feeds


def load():
    try:
        s = json.load(open(STATE))
        if isinstance(s, dict) and isinstance(s.get("feeds"), list):
            return s
    except (OSError, ValueError):
        pass
    s = {"feeds": import_island(), "imported": True}
    save(s)
    return s


def save(s):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(s, f, indent=1)
    os.replace(tmp, STATE)


def fetch(feed, refresh):
    """Raw .ics text (from the network or the cache) and an error string."""
    url = feed["url"]
    os.makedirs(CACHE, mode=0o700, exist_ok=True)
    cache = os.path.join(CACHE, feed["id"] + ".ics")
    if url.startswith("~") or url.startswith("/"):
        try:
            return open(os.path.expanduser(url), encoding="utf-8", errors="replace").read(), ""
        except OSError as e:
            return "", str(e)
    fresh = os.path.exists(cache) and (dt.datetime.now().timestamp() - os.path.getmtime(cache)) < STALE_SECS
    err = ""
    if refresh or not fresh:
        if url.startswith("webcal://"):
            url = "https://" + url[len("webcal://"):]
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "omarchy-control-center"})
            with urllib.request.urlopen(req, timeout=20) as r:
                data = r.read(MAX_BYTES + 1)
            if len(data) > MAX_BYTES:
                raise ValueError("calendar is larger than 20 MB")
            text = data.decode("utf-8", errors="replace")
            if "BEGIN:VCALENDAR" not in text:
                raise ValueError("not an iCal (.ics) calendar")
            tmp = cache + ".tmp"
            with open(tmp, "w") as f:
                f.write(text)
            os.replace(tmp, cache)
        except Exception as e:  # network down, 404, bad link: keep the cache
            err = str(e)[:200]
    try:
        return open(cache, encoding="utf-8").read(), err
    except OSError:
        return "", err or "not fetched yet"


def to_ms(v, tz):
    if isinstance(v, dt.datetime):
        if v.tzinfo is None:
            v = v.replace(tzinfo=tz)
        return int(v.timestamp() * 1000), False
    d = dt.datetime(v.year, v.month, v.day, tzinfo=tz)
    return int(d.timestamp() * 1000), True


def events_for(feed, text, start, end):
    import icalendar
    import recurring_ical_events
    cal = icalendar.Calendar.from_ical(text)
    name = str(cal.get("X-WR-CALNAME") or "")
    tz = dt.datetime.now().astimezone().tzinfo
    out = []
    for ev in recurring_ical_events.of(cal).between(start, end):
        if ev.name != "VEVENT":
            continue
        if str(ev.get("STATUS", "")).upper() == "CANCELLED":
            continue
        s = ev.get("DTSTART")
        if s is None:
            continue
        e = ev.get("DTEND")
        s_ms, all_day = to_ms(s.dt, tz)
        if e is not None:
            e_ms, _ = to_ms(e.dt, tz)
        else:
            e_ms = s_ms + (86400000 if all_day else 3600000)
        desc = str(ev.get("DESCRIPTION", "") or "")
        loc = str(ev.get("LOCATION", "") or "")
        join = ""
        for src in (str(ev.get("X-GOOGLE-CONFERENCE", "") or ""), loc, desc, str(ev.get("URL", "") or "")):
            m = JOIN_RE.search(src)
            if m:
                join = m.group(0)
                break
        out.append({
            "cal": feed["id"], "title": str(ev.get("SUMMARY", "") or "(No title)")[:200],
            "start": s_ms, "end": e_ms, "allDay": all_day,
            "location": loc[:200], "join": join,
            "uid": str(ev.get("UID", ""))[:200],
        })
    return name, out


def events(s, refresh):
    today = dt.date.today()
    first = (today.replace(day=1) - dt.timedelta(days=1)).replace(day=1)
    last = (today.replace(day=1) + dt.timedelta(days=120)).replace(day=1)
    cals, evs = [], []
    changed = False
    for f in s["feeds"]:
        info = {"id": f["id"], "name": f.get("name") or "", "color": f.get("color") or PALETTE[0],
                "enabled": f.get("enabled", True), "error": "", "host": re.sub(r"^\w+://([^/]+).*", r"\1", f["url"])[:60]}
        if info["enabled"]:
            text, err = fetch(f, refresh)
            info["error"] = err
            if text:
                try:
                    name, items = events_for(f, text, first, last)
                    evs += items
                    if name and not f.get("calname"):
                        f["calname"] = name
                        changed = True
                except Exception as e:
                    info["error"] = "could not read calendar: " + str(e)[:150]
        info["name"] = f.get("name") or f.get("calname") or info["host"]
        cals.append(info)
    if changed:
        save(s)
    evs.sort(key=lambda e: (e["start"], not e["allDay"]))
    return {"calendars": cals, "events": evs, "updated": int(dt.datetime.now().timestamp() * 1000)}


def main(argv):
    s = load()
    cmd = argv[1] if len(argv) > 1 else "events"
    refresh = "--refresh" in argv
    if cmd == "add" and len(argv) > 2:
        url = argv[2].strip()
        if not re.match(r"^(https?|webcal)://\S+$|^[~/]\S+$", url):
            print(json.dumps({"error": "That doesn't look like a calendar link"}))
            return 2
        if not any(f["url"] == url for f in s["feeds"]):
            s["feeds"].append({"id": feed_id(url), "url": url, "name": argv[3] if len(argv) > 3 else "",
                               "color": PALETTE[len(s["feeds"]) % len(PALETTE)], "enabled": True})
            save(s)
        refresh = True
    elif cmd == "remove" and len(argv) > 2:
        s["feeds"] = [f for f in s["feeds"] if f["id"] != argv[2]]
        save(s)
        try:
            os.remove(os.path.join(CACHE, argv[2] + ".ics"))
        except OSError:
            pass
    elif cmd == "set" and len(argv) > 3:
        for f in s["feeds"]:
            if f["id"] != argv[2]:
                continue
            for kv in argv[3:]:
                k, _, v = kv.partition("=")
                if k == "name":
                    f["name"] = v[:60]
                elif k == "color" and re.fullmatch(r"#[0-9a-fA-F]{6}", v):
                    f["color"] = v
                elif k == "enabled":
                    f["enabled"] = v == "true"
        save(s)
    elif cmd != "events":
        print(__doc__, file=sys.stderr)
        return 2
    print(json.dumps(events(s, refresh)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
