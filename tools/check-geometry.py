#!/usr/bin/env python3
"""Verify a 9-slice texture is safe for fcitx5 input panels.

fcitx5's classic UI (and the GTK/Qt client-side panels) slice a background image
into 3x3 cells using the theme's Margin values. Two things must hold or the
panel renders with transparent holes or smeared corners:

  1. The centre cell must have positive width and height:
         image_width  - Margin.left - Margin.right  > 0
         image_height - Margin.top  - Margin.bottom > 0
     Otherwise the centre is skipped entirely and the desktop shows through.

  2. Each edge cell must be a straight run, i.e. it must not contain part of the
     rounded corner. Otherwise stretching distorts the curvature. This is
     measured as the variance of the per-line alpha across the stretch axis; a
     straight edge scores near zero.

Usage:
    tools/check-geometry.py TEXTURE.png LEFT TOP RIGHT BOTTOM
    tools/check-geometry.py --theme THEME_DIR
"""
from __future__ import annotations

import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit("error: Pillow is required (pacman -S python-pillow)")

EDGE_VARIANCE_LIMIT = 6.0


def alpha_lines(image: Image.Image, horizontal: bool, start: int, stop: int,
                lo: int, hi: int) -> list[float]:
    """Mean alpha of each line in a strip, used for variance."""
    px = image.load()
    means = []
    if horizontal:  # strip spanning x in [lo,hi), y in [start,stop)
        for x in range(lo, hi):
            total = sum(px[x, y][3] for y in range(start, stop))
            means.append(total / (stop - start))
    else:  # strip spanning y in [lo,hi), x in [start,stop)
        for y in range(lo, hi):
            total = sum(px[x, y][3] for x in range(start, stop))
            means.append(total / (stop - start))
    return means


def variance(values: list[float]) -> float:
    if len(values) < 2:
        return 0.0
    mean = sum(values) / len(values)
    return (sum((v - mean) ** 2 for v in values) / len(values)) ** 0.5


def check(path: str, left: int, top: int, right: int, bottom: int) -> bool:
    image = Image.open(path).convert("RGBA")
    w, h = image.size
    centre_w, centre_h = w - left - right, h - top - bottom

    print(f"{path}  {w}x{h}  margin {left}/{top}/{right}/{bottom}")
    ok = True

    if centre_w <= 0 or centre_h <= 0:
        print(f"  FAIL centre cell is {centre_w}x{centre_h}; must be positive")
        print(f"       need margin < {w // 2} horizontally, < {h // 2} vertically")
        return False

    print(f"  centre cell {centre_w}x{centre_h}")

    # Top and bottom edges stretch horizontally; left and right vertically.
    checks = (
        ("top", True, 0, top, left, w - right),
        ("bottom", True, h - bottom, h, left, w - right),
        ("left", False, 0, left, top, h - bottom),
        ("right", False, w - right, w, top, h - bottom),
    )
    for name, horizontal, start, stop, lo, hi in checks:
        if horizontal and (stop - start) <= 0 or not horizontal and (stop - start) <= 0:
            continue
        score = variance(alpha_lines(image, horizontal, start, stop, lo, hi))
        status = "ok" if score <= EDGE_VARIANCE_LIMIT else "WARN"
        if score > EDGE_VARIANCE_LIMIT:
            ok = False
        print(f"  {name:<6} edge variance {score:5.2f}  {status}")

    if not ok:
        print("  hint: corners are intruding into the edge cells; "
              "increase Margin until the straight run is included")
    return ok


def main(argv: list[str]) -> int:
    if len(argv) == 3 and argv[1] == "--theme":
        import configparser
        import pathlib

        theme = pathlib.Path(argv[2])
        conf = configparser.RawConfigParser(strict=False)
        conf.optionxform = str
        conf.read(theme / "theme.conf")

        def margin(section: str) -> tuple[int, int, int, int]:
            return tuple(
                conf.getint(section, key, fallback=0)
                for key in ("Left", "Top", "Right", "Bottom")
            )  # type: ignore[return-value]

        results = []
        for image_key, section, margin_section in (
            ("Image", "InputPanel/Background", "InputPanel/Background/Margin"),
            ("Image", "InputPanel/Highlight", "InputPanel/Highlight/Margin"),
        ):
            name = conf.get(section, image_key, fallback="")
            if not name:
                continue
            path = theme / name
            if not path.exists():
                print(f"  skip {name} (missing)")
                continue
            results.append(check(str(path), *margin(margin_section)))
        return 0 if all(results) else 1

    if len(argv) != 6:
        print(__doc__)
        return 2
    return 0 if check(argv[1], *map(int, argv[2:6])) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
