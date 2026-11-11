"""Set Dynamic Island's "notifications" setting in ~/.config/omarchy/shell.json.

Usage: python3 -I island-notifications.py true|false

Only that one key of the omarchy-dynamic-island entry changes; the file is
replaced atomically. Exits 0 with no change when the island isn't installed.
"""
import json
import os
import sys
import tempfile

if len(sys.argv) != 2 or sys.argv[1] not in ("true", "false"):
    sys.exit(2)
value = sys.argv[1] == "true"
path = os.path.expanduser("~/.config/omarchy/shell.json")
with open(path) as f:
    data = json.load(f)
changed = False
for entry in data.get("plugins", []):
    if isinstance(entry, dict) and entry.get("id") == "omarchy-dynamic-island":
        if entry.get("notifications", True) != value:
            entry["notifications"] = value
            changed = True
if changed:
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
