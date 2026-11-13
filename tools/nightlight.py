#!/usr/bin/env python3
"""Night Light schedule for Control Center.

  nightlight.py status          print settings + tonight's times as JSON
  nightlight.py set KEY=VALUE…  change settings (mode, start, end, temp, dim), then apply
  nightlight.py apply           rewrite hyprsunset.conf if needed and reload hyprsunset

mode: "sun" (sunset to sunrise at your location), "custom" (start/end),
      "manual" (no schedule; the tile turns it on and off)
Settings live in ~/.local/state/omarchy/control-center/nightlight.json. The
first time hyprsunset.conf is rewritten, the original is kept next to it as
hyprsunset.conf.before-control-center.
"""
import datetime as dt
import json
import math
import os
import re
import shutil
import subprocess
import sys

HOME = os.path.expanduser("~")
STATE = os.path.join(HOME, ".local/state/omarchy/control-center/nightlight.json")
CONF = os.path.join(HOME, ".config/hypr/hyprsunset.conf")
BACKUP = CONF + ".before-control-center"
LATLON = ["/tmp/latlon.txt", os.path.join(HOME, "tmp/latlon.txt")]
HEADER = "# Managed by Control Center (Quick Settings → Night Light).\n# Change it there; edits here are replaced.\n"


def read_conf_defaults():
    """Settings implied by an existing hand-written hyprsunset.conf."""
    s = {"mode": "custom", "start": "20:00", "end": "06:00", "temp": 4500, "dim": 100}
    try:
        text = open(CONF).read()
    except OSError:
        return s
    for block in re.findall(r"profile\s*\{(.*?)\}", re.sub(r"#.*", "", text), re.S):
        t = re.search(r"time\s*=\s*(\d{1,2}:\d{2})", block)
        if not t:
            continue
        if re.search(r"identity\s*=\s*true", block):
            s["end"] = norm(t.group(1))
        else:
            s["start"] = norm(t.group(1))
            k = re.search(r"temperature\s*=\s*(\d+)", block)
            g = re.search(r"gamma\s*=\s*([\d.]+)", block)
            if k:
                s["temp"] = int(k.group(1))
            if g:
                s["dim"] = round(float(g.group(1)) * 100)
    return s


def bare(hm):
    h, m = hm.split(":")
    return "%d:%s" % (int(h), m)


def norm(hm):
    h, m = hm.split(":")
    return "%02d:%02d" % (int(h) % 24, int(m) % 60)


def load():
    try:
        s = json.load(open(STATE))
        if isinstance(s, dict):
            base = read_conf_defaults()
            base.update(s)
            return base
    except (OSError, ValueError):
        pass
    return read_conf_defaults()


def save(s):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(s, f, indent=1)
    os.replace(tmp, STATE)


def latlon():
    """Location for sunset/sunrise: a "lat lon" file if one exists, else the
    coordinates of the time zone's main city (zone1970.tab), close enough
    for a sunset schedule."""
    for p in LATLON:
        try:
            a, b = open(p).read().split()[:2]
            return float(a), float(b)
        except (OSError, ValueError):
            continue
    return tz_latlon()


def tz_latlon():
    try:
        zone = os.path.realpath("/etc/localtime").split("/zoneinfo/", 1)[1]
    except (IndexError, OSError):
        return None
    for tab in ("/usr/share/zoneinfo/zone1970.tab", "/usr/share/zoneinfo/zone.tab"):
        try:
            for line in open(tab):
                f = line.split("\t")
                if len(f) >= 3 and not line.startswith("#") and f[2].strip() == zone:
                    return iso6709(f[1])
        except OSError:
            continue
    return None


def iso6709(c):
    """'+3403-11815' or '+340308-1181434' -> (34.05, -118.25)."""
    import re
    m = re.match(r"([+-])(\d{2})(\d{2})(\d{2})?([+-])(\d{3})(\d{2})(\d{2})?$", c.strip())
    if not m:
        return None
    lat = int(m.group(2)) + int(m.group(3)) / 60 + int(m.group(4) or 0) / 3600
    lon = int(m.group(6)) + int(m.group(7)) / 60 + int(m.group(8) or 0) / 3600
    return (-lat if m.group(1) == "-" else lat, -lon if m.group(5) == "-" else lon)


def sun_times(lat, lon, day):
    """NOAA sunrise/sunset (local time, minutes precision) for `day`."""
    n = day.timetuple().tm_yday
    out = []
    for rising in (True, False):
        lng_hour = lon / 15
        t = n + ((6 if rising else 18) - lng_hour) / 24
        m = 0.9856 * t - 3.289
        l = (m + 1.916 * math.sin(math.radians(m)) + 0.020 * math.sin(math.radians(2 * m)) + 282.634) % 360
        ra = math.degrees(math.atan(0.91764 * math.tan(math.radians(l)))) % 360
        ra = (ra + (math.floor(l / 90) * 90 - math.floor(ra / 90) * 90)) / 15
        sin_dec = 0.39782 * math.sin(math.radians(l))
        cos_dec = math.cos(math.asin(sin_dec))
        cos_h = (math.cos(math.radians(90.833)) - sin_dec * math.sin(math.radians(lat))) / (cos_dec * math.cos(math.radians(lat)))
        if not -1 <= cos_h <= 1:
            return None  # polar day/night
        h = (360 - math.degrees(math.acos(cos_h))) if rising else math.degrees(math.acos(cos_h))
        local_t = h / 15 + ra - 0.06571 * t - 6.622
        utc = (local_t - lng_hour) % 24
        base = dt.datetime(day.year, day.month, day.day, tzinfo=dt.timezone.utc)
        when = (base + dt.timedelta(hours=utc)).astimezone()
        out.append(when.strftime("%H:%M"))
    return out  # [sunrise, sunset]


def schedule(s):
    """(start, end) hyprsunset should use, or None for manual."""
    if s["mode"] == "manual":
        return None
    if s["mode"] == "sun":
        ll = latlon()
        st = sun_times(*ll, dt.date.today()) if ll else None
        if st:
            return st[1], st[0]
    return norm(s["start"]), norm(s["end"])


def render(s):
    sch = schedule(s)
    gamma = max(0.3, min(1.0, s["dim"] / 100))
    if sch is None:
        return HEADER + "# Schedule off: Night Light only turns on from Quick Settings.\nprofile {\n    time = 0:00\n    identity = true\n}\n"
    start, end = sch
    return (HEADER + "profile {\n    time = %s\n    identity = true\n}\n\nprofile {\n    time = %s\n    temperature = %d\n    gamma = %.2f\n}\n"
            % (bare(end), bare(start), int(s["temp"]), gamma))


def apply(s):
    text = render(s)
    try:
        cur = open(CONF).read()
    except OSError:
        cur = None
    if cur == text:
        return False
    if cur is not None and not cur.startswith(HEADER) and not os.path.exists(BACKUP):
        shutil.copy2(CONF, BACKUP)
    tmp = CONF + ".tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, CONF)
    restart_hyprsunset()
    return True


def restart_hyprsunset():
    """Reload hyprsunset so it reads the new schedule (it applies the profile
    for the current time on start)."""
    import time
    subprocess.run(["pkill", "-x", "hyprsunset"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(20):
        if subprocess.run(["pgrep", "-x", "hyprsunset"], stdout=subprocess.DEVNULL).returncode != 0:
            break
        time.sleep(0.1)
    # Its own transient user service: it must outlive this script and the
    # shell (anything started as our child dies with our cgroup).
    subprocess.run(["systemd-run", "--user", "--collect", "--quiet", "--", "hyprsunset"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def status(s):
    ll = latlon()
    st = sun_times(*ll, dt.date.today()) if ll else None
    sch = schedule(s)
    out = dict(s)
    out.update({"sunrise": st[0] if st else "", "sunset": st[1] if st else "",
                "from": sch[0] if sch else "", "to": sch[1] if sch else "", "hasLocation": bool(st)})
    return out


def main(argv):
    s = load()
    cmd = argv[1] if len(argv) > 1 else "status"
    if cmd == "set":
        for kv in argv[2:]:
            k, _, v = kv.partition("=")
            if k == "mode" and v in ("sun", "custom", "manual"):
                s["mode"] = v
            elif k in ("start", "end") and re.fullmatch(r"\d{1,2}:\d{2}", v):
                s[k] = norm(v)
            elif k == "temp" and v.isdigit():
                s["temp"] = max(2500, min(6000, int(v)))
            elif k == "dim" and v.isdigit():
                s["dim"] = max(30, min(100, int(v)))
            else:
                print("bad setting: " + kv, file=sys.stderr)
                return 2
        save(s)
        apply(s)
    elif cmd == "apply":
        # Never take over a hand-written hyprsunset.conf: only once settings
        # have been chosen in Quick Settings.
        if not os.path.exists(STATE):
            print("unmanaged")
            return 0
        print("changed" if apply(s) else "same")
        return 0
    elif cmd != "status":
        print(__doc__, file=sys.stderr)
        return 2
    print(json.dumps(status(s)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
