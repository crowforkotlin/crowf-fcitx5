# crowf-fcitx5

Everything fcitx5 needs to render a correct candidate panel in **every** client,
including the ones that draw the window themselves.

The Mellow colour schemes are vendored, repaired, and installed together.

## the bug this repository fixes

fcitx5 does not have one candidate window. It has two, and they disagree about
what a theme means:

| painter | used by | reads |
| --- | --- | --- |
| `classicui` | apps that delegate the panel to the fcitx5 daemon | `Image`, SVG **and** PNG |
| client-side panel | Qt/GTK apps that ask for the candidate list over D-Bus, including WeChat, which draws it with its own embedded `fcitx::FcitxCandidateWindow` | the colour keys in `theme.conf`, plus PNG |

Two consequences, both visible in real apps:

1. **SVG-only themes lose their corners.** WeChat statically links Qt 5.15 and
   loads no imageformat plugins, so it has no SVG decoder at all. A theme whose
   assets are SVG drops to a flat, square, often white rectangle.
2. **A `HighlightBackgroundColor` that does not match the highlight texture
   makes the two painters choose different fills.** The stock Mellow themes
   declare `#a5a5a5` for every scheme while their `highlight.svg` is actually
   `#c73e3a`, `#31a870`, `#1781b5`, … classicui paints a coloured pill; the
   client panel paints grey under the same text.

The second one is what makes a selected candidate unreadable: the foreground
was chosen against one fill and lands on the other. Contrast is checked against
the texture the theme actually ships, not against the number someone typed.

## install

```bash
git clone https://github.com/crowforkotlin/crowf-fcitx5.git
cd crowf-fcitx5
./install.sh                  # all ten themes
./install.sh --theme mellow-wechat-dark   # just one
./install.sh --check          # audit what is installed, change nothing
./install.sh --uninstall      # remove the installed themes
```

Then select one:

```ini
# ~/.config/fcitx5/conf/classicui.conf
Theme=mellow-graphite-dark
DarkTheme=mellow-graphite-dark
```

```bash
pkill -x fcitx5 && fcitx5 -d      # fcitx5 only reads the theme at startup
```

Dependency: `python3` + `python-pillow`, used by the installer's audit step.

## what ships

| scheme | base | `-dark` panel |
| --- | --- | --- |
| graphite | light panel | `#151515` |
| sakura | light panel | `#151515` |
| vermilion | light panel | `#151515` |
| wechat | light panel | `#151515` |
| youlan | light panel | `#151515` |

Every theme ships `panel.svg` + `panel.png` + `highlight.svg` +
`highlight.png` + `theme.conf`. PNG is not a convenience: it is the only format
all three painters can decode.

Upstream Mellow themes are BSD-2-Clause, © sanweiya. See `LICENSE`.

## colour rules

`tools/fix-contrast.py` enforces these; `install.sh` runs it after copying so a
regression cannot be installed silently.

| key | must satisfy |
| --- | --- |
| `HighlightBackgroundColor` | equal to the highlight texture's centre fill |
| `HighlightCandidateColor` | ≥ 4.5:1 on that fill |
| `HighlightColor` | alias for the same text, kept in step |
| `NormalColor` | ≥ 4.5:1 on the panel fill |
| `[*/Background] Color=` | present whenever `Image=` is set |

```bash
./tools/fix-contrast.py --check --all   # report
./tools/fix-contrast.py --fix --all     # repair in place
```

The fixer picks black or white by whichever *actually* contrasts more, not by a
luminance threshold. Mid-tone fills break the threshold approach: `#31a870` has
luminance 0.30 but reads far better with black (6.97:1) than white (3.01:1).

Textures are measured from the PNG's centre pixel — the centre cell of a
nine-slice texture is a flat fill by construction. SVG is deliberately not
parsed: it is not what the client panels decode, so its fill says nothing about
what they paint.

## dynamic colours (optional, not shipped)

If you drive matugen from your dotfiles — as
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) does — add
the templates yourself. This repository no longer ships a theme of its own; it
installs the static schemes above and leaves the wallpaper-driven one to your
matugen setup.

Two matugen details that are easy to get wrong:

- **`{{colors.<name>.default.hex}}` follows the current mode, so a variant with
  a hardcoded panel colour must not use it.** A "black" theme with
  `Color=#000000` and `NormalColor={{colors.on_surface.default.hex}}` renders
  `#161d1d` on black (1.23:1) whenever matugen runs in light mode. Pin the
  accessor instead: `{{colors.on_surface.dark.hex}}`.
- **`post_hook` is a shell string**, run after the file is written. That is how
  a PNG gets produced next to the SVG.

## layout

```
install.sh                  install / audit / uninstall
themes/mellow-*/            vendored, repaired themes (theme.conf + 2 svg + 2 png)
tools/fix-contrast.py       contrast + asset audit and repair
tools/check-geometry.py     nine-slice validator
packaging/PKGBUILD          AUR package
```

## design constraints (read before editing a texture)

Panels are drawn with 3×3 nine-slice scaling: corners are copied, edges are
stretched. So the centre cell must stay non-empty (`size - Margin > 0`) and each
edge must be a straight run, or corners get smeared along the panel.

```bash
python3 tools/check-geometry.py --theme themes/mellow-graphite-dark
```

## license

MIT for the tooling. Vendored themes are BSD-2-Clause, © sanweiya
([fcitx5-mellow-themes](https://github.com/sanweiya/fcitx5-mellow-themes)).
