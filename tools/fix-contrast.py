#!/usr/bin/env python3
"""Audit and repair fcitx5 candidate-panel colours.

Why the colour keys matter more than the images
-----------------------------------------------
fcitx5 paints the highlighted candidate two ways:

  * classicui — the daemon's own Pango/Cairo window. It decodes both SVG and
    PNG, so it honours ``[InputPanel/Highlight] Image`` verbatim.
  * client-side panels — what Qt and GTK apps ask for over D-Bus, including the
    window WeChat draws with its own embedded ``fcitx::FcitxCandidateWindow``.
    Those read the *colour keys* in ``theme.conf``. WeChat's copy is statically
    linked Qt 5.15 and loads no imageformat plugins, so it has no SVG decoder at
    all; PNG-only assets are the safe common denominator.

That split is what produces the "selected candidate is unreadable" symptom:
classicui paints the texture (e.g. red), the client paints
``HighlightBackgroundColor`` (e.g. grey), and if ``HighlightCandidateColor``
was chosen against only one of them the other turns into text-on-text.

Rules enforced
--------------
  HighlightBackgroundColor   describes the highlight texture. When the texture
                             is a raster we can read, this key must equal its
                             centre fill — otherwise the two painters disagree.
  HighlightCandidateColor    text on the highlighted candidate. Must reach
                             MIN_CONTRAST against the highlight fill.
  HighlightColor             alias used by some themes for the same text; kept
                             in step with HighlightCandidateColor.
  NormalColor                text on unhighlighted candidates. Must reach
                             MIN_CONTRAST against the panel fill.
  [*/Background] Color=      fallback for clients that cannot decode Image at
                             all. Present whenever Image= is present.

An image whose colour cannot be verified (SVG with no raster sibling) is
reported but never silently "fixed" — that needs a human decision about which
of the two painters to trust.

Usage
-----
    tools/fix-contrast.py --check THEME_DIR...   report only; exit 1 on issues
    tools/fix-contrast.py --fix   THEME_DIR...   rewrite offending keys
    tools/fix-contrast.py --check --all          every installed theme
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit("error: Pillow is required (pacman -S python-pillow)")

MIN_CONTRAST = 4.5

# Sections that can name an Image= and therefore also need a Color= fallback.
IMAGE_SECTIONS = (
    "InputPanel/Background",
    "InputPanel/Highlight",
    "Menu/Background",
    "Menu/Highlight",
)


def rel_luminance(hexcolor: str) -> float:
    value = hexcolor.lstrip("#")
    if len(value) == 8:  # contrast is defined on opaque colour
        value = value[:6]
    channels = [int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)]
    linear = [
        c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
        for c in channels
    ]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast(fg: str, bg: str) -> float:
    a, b = rel_luminance(fg), rel_luminance(bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def pick_text(fill: str, current: str = "") -> str:
    """Colour with enough contrast on `fill`.

    The current value is kept when it already passes. Otherwise choose whichever
    of black/white actually contrasts more on this fill — a luminance threshold
    is not sufficient, because mid-tone fills such as #31a870 sit below 0.5 yet
    read far better with black (6.97:1) than white (3.01:1).
    """
    if current and contrast(current, fill) >= MIN_CONTRAST:
        return current
    black, white = contrast("#000000", fill), contrast("#ffffff", fill)
    return "#000000" if black >= white else "#ffffff"


def raster_fill(path: pathlib.Path) -> str | None:
    """Centre pixel of a rendered texture as #rrggbb.

    The centre cell of a 9-slice texture is flat by construction, so the middle
    pixel is the authoritative colour whatever the corner radius.

    SVG returns None on purpose: this measures what the client-side panels can
    actually decode, and neither WeChat's static Qt nor the GTK client ships an
    SVG image plugin.
    """
    if not path.exists() or path.suffix.lower() == ".svg":
        return None
    image = Image.open(path).convert("RGBA")
    w, h = image.size
    r, g, b, _ = image.getpixel((w // 2, h // 2))
    return f"#{r:02x}{g:02x}{b:02x}"


def parse(path: pathlib.Path) -> dict[str, dict[str, str]]:
    sections: dict[str, dict[str, str]] = {}
    current = ""
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            current = stripped[1:-1]
            sections.setdefault(current, {})
        elif "=" in stripped and not stripped.startswith("#"):
            key, _, value = stripped.partition("=")
            sections.setdefault(current, {})[key.strip()] = value.strip()
    return sections


def rewrite(path: pathlib.Path, updates: dict[str, dict[str, str]]) -> None:
    """Apply key updates, preserving comments, ordering and formatting.

    Existing keys are replaced in place. Keys that do not exist yet are appended
    to the end of their section, which is required for the `Color=` fallbacks:
    a theme that never declared one still needs it, and a replacement-only
    writer would silently report success while changing nothing.
    """
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    pending = {section: dict(keys) for section, keys in updates.items()}
    current = ""
    out: list[str] = []
    last_line_of_section: dict[str, int] = {}

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            current = stripped[1:-1]
            out.append(line)
            last_line_of_section[current] = len(out) - 1
            continue
        if "=" in stripped and not stripped.startswith("#") and current in updates:
            key = stripped.partition("=")[0].strip()
            if key in updates[current]:
                newline = "\n" if line.endswith("\n") else ""
                out.append(f"{key}={updates[current][key]}{newline}")
                pending.get(current, {}).pop(key, None)
                last_line_of_section[current] = len(out) - 1
                continue
        out.append(line)
        # Track the last *content* line so appended keys land inside the
        # section, not after the blank line that separates it from the next.
        if current in updates and stripped and not stripped.startswith("#"):
            last_line_of_section[current] = len(out) - 1

    # Append keys that were never present, in section order, right after the
    # section's last line so they still belong to it.
    inserts: dict[int, list[str]] = {}
    for section, keys in pending.items():
        if not keys or section not in last_line_of_section:
            continue
        inserts.setdefault(last_line_of_section[section], []).extend(
            f"{key}={value}\n" for key, value in keys.items())
    for index in sorted(inserts, reverse=True):
        out[index + 1:index + 1] = inserts[index]

    path.write_text("".join(out), encoding="utf-8")


def audit(theme: pathlib.Path, fix: bool) -> list[str]:
    conf_path = theme / "theme.conf"
    if not conf_path.exists():
        return [f"{theme.name}: no theme.conf"]

    sec = parse(conf_path)
    panel = sec.get("InputPanel", {})
    bg = sec.get("InputPanel/Background", {})
    hl = sec.get("InputPanel/Highlight", {})

    problems: list[str] = []
    updates: dict[str, dict[str, str]] = {}

    def note(message: str) -> None:
        problems.append(message)

    # ---- highlight: what colour does each painter actually use? ----------
    hl_fill = raster_fill(theme / hl["Image"]) if hl.get("Image") else None
    declared = panel.get("HighlightBackgroundColor") or hl.get("Color")

    if hl_fill and declared and hl_fill.lower() != declared.lower():
        note(f"{theme.name}: HighlightBackgroundColor {declared} but highlight "
             f"texture is {hl_fill}; classicui and client panels disagree")
        # The texture wins: it is what classicui shows most of the time, and
        # rewriting the colour keeps both painters identical.
        updates.setdefault("InputPanel", {})["HighlightBackgroundColor"] = hl_fill
        if hl.get("Color") and hl["Color"].lower() != hl_fill.lower():
            updates.setdefault("InputPanel/Highlight", {})["Color"] = hl_fill

    highlight_fill = hl_fill or declared
    if highlight_fill:
        text = panel.get("HighlightCandidateColor") or panel.get("HighlightColor")
        if text and contrast(text, highlight_fill) < MIN_CONTRAST:
            note(f"{theme.name}: HighlightCandidateColor {text} on "
                 f"{highlight_fill} = {contrast(text, highlight_fill):.2f}:1")
            replacement = pick_text(highlight_fill,
                                    panel.get("HighlightCandidateColor", ""))
            updates.setdefault("InputPanel", {})["HighlightCandidateColor"] = replacement
            if panel.get("HighlightColor"):
                updates.setdefault("InputPanel", {})["HighlightColor"] = replacement

    # ---- normal candidates ------------------------------------------------
    panel_fill = raster_fill(theme / bg["Image"]) if bg.get("Image") else None
    panel_fill = panel_fill or bg.get("Color")
    if panel_fill and panel.get("NormalColor"):
        if contrast(panel["NormalColor"], panel_fill) < MIN_CONTRAST:
            note(f"{theme.name}: NormalColor {panel['NormalColor']} on "
                 f"{panel_fill} = {contrast(panel['NormalColor'], panel_fill):.2f}:1")
            updates.setdefault("InputPanel", {})["NormalColor"] = pick_text(
                panel_fill, panel.get("NormalColor", ""))

    # ---- image sections need a colour fallback ---------------------------
    for section in IMAGE_SECTIONS:
        data = sec.get(section, {})
        if not data.get("Image"):
            continue
        if not data.get("Color"):
            note(f"{theme.name}: [{section}] Image={data['Image']} but no Color=")
            fill = raster_fill(theme / data["Image"])
            if fill:
                updates.setdefault(section, {})["Color"] = fill
        if data["Image"].lower().endswith(".svg"):
            raster = theme / (data["Image"][:-4] + ".png")
            if not raster.exists():
                note(f"{theme.name}: [{section}] {data['Image']} has no .png "
                     f"sibling; static Qt clients cannot decode SVG")

    if fix and updates:
        rewrite(conf_path, updates)
    return problems


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="report only")
    mode.add_argument("--fix", action="store_true", help="rewrite offending keys")
    parser.add_argument("--all", action="store_true",
                        help="every theme under $XDG_DATA_HOME/fcitx5/themes")
    parser.add_argument("themes", nargs="*", type=pathlib.Path)
    args = parser.parse_args(argv[1:])

    targets = list(args.themes)
    if args.all:
        import os
        root = pathlib.Path(os.environ.get("XDG_DATA_HOME",
                                           pathlib.Path.home() / ".local/share"))
        themes_dir = root / "fcitx5/themes"
        targets.extend(sorted(p for p in themes_dir.iterdir() if p.is_dir()))
    if not targets:
        parser.error("no themes given (use --all or pass paths)")

    total = 0
    for theme in targets:
        problems = audit(theme, fix=args.fix)
        if problems:
            total += len(problems)
            for problem in problems:
                print(("  fixed: " if args.fix else "  ") + problem)
        elif args.check:
            print(f"  {theme.name}: ok")

    if total and not args.fix:
        print(f"\n{total} problem(s). Re-run with --fix to repair.")
        return 1
    if total:
        print(f"\nfixed {total} problem(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
