#!/usr/bin/env python3
"""Render crowf-fcitx5 theme assets and verify the 9-slice geometry.

Two modes:

    tools/render.py --static            render the shipped dark/light PNGs
    tools/render.py --check             validate everything already on disk

The matugen path does not use this script: matugen fills the {{...}}
placeholders itself and runs rsvg-convert through a post_hook (see install.sh).
This script exists so the repository can ship working PNGs without requiring
matugen, and so contributors can validate geometry before committing.

Why PNG and not SVG
-------------------
fcitx5's own UI (classicui) and the GTK client panel both decode SVG, but the
candidate window drawn by the Qt frontend — which is what WeChat uses — has no
SVG decoder compiled in. Its theme loader falls back to a flat fill rectangle
when the image fails to load, so an SVG-only theme loses rounded corners there.
PNG is decoded natively by all three, so the theme ships PNG and keeps the SVG
only as the editable source.
"""
from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SIZE = 48  # must match the canvas in src/*/*.svg and the Margin values

# Panel/highlight fills for the shipped static themes. Keep in sync with
# themes/crowf-*/theme.conf.
PALETTES = {
    "dark": {
        "panel_fill": "#1a2121",
        "panel_stroke": "#3f4949",
        "highlight_fill": "#80d4d8",
    },
    "light": {
        "panel_fill": "#e9efef",
        "panel_stroke": "#bec8c8",
        "highlight_fill": "#80d4d8",
    },
}

SOURCES = {
    "panel": ROOT / "src" / "panels" / "panel.svg",
    "highlight": ROOT / "src" / "highlights" / "highlight.svg",
}


def fill(template: str, values: dict[str, str]) -> str:
    out = template
    for key, value in values.items():
        out = out.replace("{{" + key + "}}", value)
    left = [part for part in out.split("{{")[1:]]
    if left:
        missing = [part.split("}}", 1)[0] for part in left]
        raise SystemExit(f"error: unfilled placeholders: {sorted(set(missing))}")
    return out


def render(variant: str) -> None:
    values = PALETTES[variant]
    outdir = ROOT / "themes" / f"crowf-{variant}"
    outdir.mkdir(parents=True, exist_ok=True)
    for asset, source in SOURCES.items():
        svg_text = fill(source.read_text(), values)
        svg_path = outdir / f"{asset}.svg"
        svg_path.write_text(svg_text)
        subprocess.run(
            ["rsvg-convert", "-w", str(SIZE), "-h", str(SIZE), str(svg_path),
             "-o", str(outdir / f"{asset}.png")],
            check=True,
        )
        print(f"  {outdir.relative_to(ROOT)}/{asset}.png")


def check() -> int:
    failures = 0
    for variant in PALETTES:
        theme = ROOT / "themes" / f"crowf-{variant}"
        if not theme.exists():
            print(f"  {variant}: not rendered yet (run --static)")
            failures += 1
            continue
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools" / "check-geometry.py"),
             "--theme", str(theme)],
            capture_output=True, text=True,
        )
        print(result.stdout.rstrip())
        if result.returncode != 0:
            failures += 1
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--static", action="store_true",
                       help="render the shipped dark and light themes")
    group.add_argument("--check", action="store_true",
                       help="verify geometry of the rendered themes")
    args = parser.parse_args()

    if args.static:
        for variant in PALETTES:
            print(f"rendering crowf-{variant}")
            render(variant)
        return 0
    return check()


if __name__ == "__main__":
    raise SystemExit(main())
