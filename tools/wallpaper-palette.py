#!/usr/bin/env python3
"""Colours of the current Omarchy wallpaper, for the glass border's rim.

Prints JSON: {"path": ..., "accent": "rrggbb", "base": "rrggbb"} where
`accent` is the most vivid colour that covers a fair share of the picture and
`base` its most common colour. Videos and unreadable files give nulls.
Uses ImageMagick (`magick`), which Omarchy ships.
"""
import colorsys
import json
import os
import re
import subprocess

LINK = os.path.expanduser("~/.local/state/omarchy/current/background")


def histogram(path):
    out = subprocess.run(
        ["magick", path + "[0]", "-resize", "160x160^", "-gravity", "center", "-extent", "160x160",
         "+dither", "-colors", "8", "-format", "%c", "histogram:info:-"],
        capture_output=True, text=True, timeout=20).stdout
    hist = []
    for line in out.splitlines():
        m = re.match(r"\s*(\d+):.*#([0-9A-Fa-f]{6})", line)
        if m:
            hist.append((int(m.group(1)), m.group(2).lower()))
    return hist


def main():
    path = os.path.realpath(LINK)
    result = {"path": path, "accent": None, "base": None}
    if os.path.isfile(path) and not re.search(r"\.(mp4|webm|mov|mkv)$", path, re.I):
        try:
            hist = histogram(path)
        except (OSError, subprocess.SubprocessError):
            hist = []
        if hist:
            total = sum(c for c, _ in hist)
            result["base"] = max(hist)[1]

            def score(item):
                count, hexv = item
                r, g, b = (int(hexv[i:i + 2], 16) / 255 for i in (0, 2, 4))
                h, l, s = colorsys.rgb_to_hls(r, g, b)
                # Vivid, neither near-black nor near-white, and not a speck.
                share = count / total
                return s * (1 - abs(l - 0.55) * 1.4) * min(1.0, share * 8)

            result["accent"] = max(hist, key=score)[1]
    print(json.dumps(result))


if __name__ == "__main__":
    main()
