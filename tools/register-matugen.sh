#!/usr/bin/env bash
# Register crowf-fcitx5 with an EXISTING matugen config.
#
# Use this when something else already drives matugen for you — dotfiles that
# symlink ~/.config/matugen, DankMaterialShell, a wallpaper daemon, etc. The
# entries are appended to that config, so every time it regenerates (theme
# switch, wallpaper change, `dms ipc call theme toggle`) the fcitx5 theme is
# recoloured along with everything else. No second regeneration mechanism.
#
# Usage:
#   tools/register-matugen.sh                       append to ~/.config/matugen/config.toml
#   tools/register-matugen.sh --config PATH         use a different config file
#   tools/register-matugen.sh --theme-dir DIR       write the theme elsewhere
#   tools/register-matugen.sh --print               show the block, change nothing
#   tools/register-matugen.sh --uninstall           remove the block again
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SELF_DIR")"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/matugen/config.toml"
THEME_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/themes/crowf"

DO_PRINT=0
DO_UNINSTALL=0
while (($#)); do
    case "$1" in
    --config)
        CONFIG="$2"
        shift
        ;;
    --theme-dir)
        THEME_DIR="$2"
        shift
        ;;
    --print) DO_PRINT=1 ;;
    --uninstall) DO_UNINSTALL=1 ;;
    -h | --help)
        sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "unknown option: $1" >&2
        exit 1
        ;;
    esac
    shift
done

BEGIN_MARK="# >>> crowf-fcitx5 >>>"
END_MARK="# <<< crowf-fcitx5 <<<"

# post_hook must be a plain string (not a TOML table) and runs after each write.
# 48x48 matches the SVG canvas; see tools/check-geometry.py for why that and the
# Margin values have to agree.
read -r -d '' BLOCK <<EOF || true
$BEGIN_MARK
[templates.crowf_theme]
input_path = '$ROOT/matugen/templates/crowf/theme.conf'
output_path = '$THEME_DIR/theme.conf'

[templates.crowf_panel]
input_path = '$ROOT/matugen/templates/crowf/panel.svg'
output_path = '$THEME_DIR/panel.svg'
post_hook = 'rsvg-convert -w 48 -h 48 $THEME_DIR/panel.svg -o $THEME_DIR/panel.png'

[templates.crowf_highlight]
input_path = '$ROOT/matugen/templates/crowf/highlight.svg'
output_path = '$THEME_DIR/highlight.svg'
post_hook = 'rsvg-convert -w 48 -h 48 $THEME_DIR/highlight.svg -o $THEME_DIR/highlight.png'
$END_MARK
EOF

if ((DO_PRINT)); then
    printf '%s\n' "$BLOCK"
    exit 0
fi

if ((DO_UNINSTALL)); then
    [[ -f $CONFIG ]] || {
        echo "error: $CONFIG not found" >&2
        exit 1
    }
    python3 - "$CONFIG" "$BEGIN_MARK" "$END_MARK" <<'PY'
import pathlib, sys
path, begin, end = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text()
if begin not in text:
    print("  nothing to remove")
    raise SystemExit(0)
start = text.index(begin)
stop = text.index(end, start) + len(end)
out = text[:start].rstrip("\n") + "\n" + text[stop:].lstrip("\n")
path.write_text(out)
print(f"  removed crowf-fcitx5 block from {path}")
PY
    exit 0
fi

mkdir -p "$(dirname "$CONFIG")" "$THEME_DIR"
touch "$CONFIG"

if grep -q "$BEGIN_MARK" "$CONFIG"; then
    echo "  already registered in $CONFIG"
    echo "  (remove with --uninstall, then re-run to pick up new paths)"
    exit 0
fi

printf '\n%s\n' "$BLOCK" >>"$CONFIG"
echo "  appended crowf-fcitx5 template entries to $CONFIG"
echo "  theme output: $THEME_DIR"
cat <<'EOF'

Now regenerate with whatever already drives matugen, for example:
    dms ipc call theme toggle && dms ipc call theme dark
    matugen image /path/to/wallpaper.jpg -m dark

and select the theme once:
    Theme=crowf   in ~/.config/fcitx5/conf/classicui.conf
EOF
