#!/usr/bin/env bash
# Generate crowf-fcitx5 colours from a wallpaper with matugen.
#
# This is the standalone path: it builds its own matugen config, so the theme
# works whether or not you already have a matugen setup. If you do have one
# (dotfiles, DankMaterialShell, ...), use tools/register-matugen.sh instead so
# both regenerate on the same trigger.
#
# Usage:
#   tools/generate.sh IMAGE                 dark variant, default paths
#   tools/generate.sh IMAGE --mode light    light variant
#   tools/generate.sh '#4a90d9'             from a hex colour instead
#   tools/generate.sh IMAGE --theme-dir DIR write somewhere other than the default
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SELF_DIR")"
DEFAULT_THEME_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/themes/crowf"

MODE="dark"
THEME_DIR="$DEFAULT_THEME_DIR"
PREFER="saturation"

SOURCE=""
while (($#)); do
    case "$1" in
    --mode)
        MODE="$2"
        shift
        ;;
    --theme-dir)
        THEME_DIR="$2"
        shift
        ;;
    --prefer)
        PREFER="$2"
        shift
        ;;
    -h | --help)
        sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        SOURCE="$1"
        ;;
    esac
    shift
done

if [[ -z $SOURCE ]]; then
    echo "error: pass a wallpaper path or a #rrggbb colour" >&2
    exit 1
fi

for tool in matugen rsvg-convert; do
    command -v "$tool" >/dev/null || {
        echo "error: $tool is required" >&2
        exit 1
    }
done

mkdir -p "$THEME_DIR"
CONFIG="$(mktemp)"
trap 'rm -f "$CONFIG"' EXIT

# post_hook is a plain shell string, not a TOML table. It runs after each file
# is written, which is how the PNG appears next to the SVG. The 48x48 size must
# match the canvas in matugen/templates/crowf/*.svg and the Margin values in
# theme.conf, or the nine-slice slicing lands in the wrong place.
cat >"$CONFIG" <<EOF
[config]

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
EOF

if [[ $SOURCE == \#* ]]; then
    matugen color hex "${SOURCE#\#}" -c "$CONFIG" -m "$MODE"
else
    matugen image "$SOURCE" -c "$CONFIG" -m "$MODE" --prefer="$PREFER"
fi

echo "  wrote $THEME_DIR"
echo "  restart fcitx5 to pick it up: fcitx5 -r -d"
