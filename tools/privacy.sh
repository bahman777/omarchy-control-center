#!/bin/bash
# Which apps are using the camera or the microphone right now.
# Prints two lines:  cam:<app,app>  and  mic:<app,app>  (empty when none).
#
# Camera: processes holding a /dev/video* device open (only this user's
# processes are visible, which is the point). PipeWire's own device monitor
# is not "use". Microphone: active (uncorked) recording streams on a real
# input; level meters (pavucontrol, peak monitors) and recordings of an
# output's monitor (visualisers, screen recorders' system audio) aren't.

cam=$(find /proc/[0-9]*/fd -maxdepth 1 -lname '/dev/video*' 2>/dev/null |
  cut -d/ -f3 | sort -u | while read -r pid; do cat "/proc/$pid/comm" 2>/dev/null; done |
  grep -vxE 'pipewire|wireplumber' | sort -u | paste -sd, -)

mic=$(python3 -I -c '
import json, os, subprocess
def pa(what):
    r = subprocess.run(["pactl", "-f", "json", "list", what], capture_output=True, text=True,
                       env=dict(os.environ, LC_ALL="C"), timeout=3)
    return json.loads(r.stdout or "[]")
try:
    outs = pa("source-outputs")
    srcs = {s.get("index"): s.get("name", "") for s in pa("sources")} if outs else {}
except Exception:
    outs, srcs = [], {}
names = set()
for o in outs:
    p = o.get("properties", {})
    if o.get("corked") or p.get("stream.monitor") == "true" or "peak" in p.get("media.name", "").lower():
        continue
    if p.get("application.id") == "org.PulseAudio.pavucontrol":
        continue
    if srcs.get(o.get("source"), "").endswith(".monitor"):
        continue
    names.add(p.get("application.name") or p.get("application.process.binary") or p.get("node.name") or "app")
print(",".join(sorted(names)))
' 2>/dev/null)

echo "cam:$cam"
echo "mic:$mic"
