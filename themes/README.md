# Vendored themes

Ten Mellow colour schemes from
[sanweiya/fcitx5-mellow-themes](https://github.com/sanweiya/fcitx5-mellow-themes),
BSD-2-Clause (see `LICENSE` in this directory), then repaired here.

## what was changed from upstream

Upstream ships **SVG only** and declares a `HighlightBackgroundColor` that does
not match its own highlight texture. Both break the client-side candidate
panel, which cannot decode SVG and paints the colour key instead of the image.
The result in WeChat is a square white panel; in QQ, dark text on a
`HighlightBackgroundColor` that never matched the pill.

Per theme:

1. `panel.png` / `highlight.png` rendered from the upstream SVGs, so clients
   without an SVG decoder keep the rounded shape.
2. `HighlightBackgroundColor` set to the highlight texture's actual fill
   (upstream used `#a5a5a5` for every scheme regardless of colour).
3. `HighlightCandidateColor` / `HighlightColor` re-picked where the existing
   value fell below 4.5:1 on that fill.
4. `NormalColor` re-picked where it fell below 4.5:1 on the panel fill.
5. `Color=` added to every `[*/Background]` and `[*/Highlight]` section that
   names an `Image=`, so a client that skips the image still gets the right fill.

Verify with:

```bash
../tools/fix-contrast.py --check .
```

Re-running that with `--fix` is safe and idempotent.
