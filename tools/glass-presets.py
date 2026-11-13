#!/usr/bin/env python3
"""List the hyprglass presets defined in ~/.config/hypr/*.lua, as JSON.

Reads only. Finds `hg.preset("name", { ... })` (or `...hyprglass.preset(`)
blocks and the `default_preset` set in `hg.config({...})`, and keeps the
top-level `key = value` fields of each preset (numbers, 0x colours, strings,
booleans; nested `dark = {...}` / `light = {...}` tables are skipped).

Output: {"presets": {name: {field: value, ...}}, "order": [...], "default": name}
"""
import glob
import json
import os
import re

HYPR = os.path.expanduser("~/.config/hypr")
PRESET = re.compile(r'(?:\bhg|hyprglass)\s*\.\s*preset\s*\(\s*"([^"]+)"\s*,\s*\{')
CONFIG = re.compile(r'(?:\bhg|hyprglass)\s*\.\s*config\s*\(\s*\{')
FIELD = re.compile(r'([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(0x[0-9A-Fa-f]+|-?\d+(?:\.\d+)?|"[^"]*"|true|false)')


def strip_comments(text):
    return re.sub(r'--\[\[.*?\]\]|--[^\n]*', '', text, flags=re.S)


def block(text, start):
    """Body of the {...} that opens just before `start`, top level only."""
    depth, i, body = 1, start, []
    while i < len(text) and depth:
        c = text[i]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                break
        if depth == 1:
            body.append(c)
        elif c == '{' and depth == 2:
            body.append(' ')
        i += 1
    return ''.join(body)


def value(raw):
    if raw.startswith('"'):
        return raw[1:-1]
    if raw in ('true', 'false'):
        return raw == 'true'
    if raw.lower().startswith('0x'):
        return int(raw, 16)
    return float(raw) if '.' in raw else int(raw)


def main():
    presets, order, default = {}, [], ""
    files = sorted(f for f in glob.glob(os.path.join(HYPR, "*.lua")) if ".bak" not in f)
    # The plugin's own file last, so a saved preset wins like it does at load.
    files.sort(key=lambda f: f.endswith("control-center.lua"))
    for f in files:
        try:
            text = strip_comments(open(f, encoding="utf-8", errors="replace").read())
        except OSError:
            continue
        for m in PRESET.finditer(text):
            fields = {k: value(v) for k, v in FIELD.findall(block(text, m.end()))}
            presets[m.group(1)] = fields
            if m.group(1) not in order:
                order.append(m.group(1))
        for m in CONFIG.finditer(text):
            d = re.search(r'default_preset\s*=\s*"([^"]+)"', block(text, m.end()))
            if d:
                default = d.group(1)
    print(json.dumps({"presets": presets, "order": order, "default": default}))


if __name__ == "__main__":
    main()
