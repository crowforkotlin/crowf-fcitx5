#!/usr/bin/env bash
# crowf-fcitx5 installer.
#
# Copies the theme into the fcitx5 data directory and optionally wires up
# matugen so the colours follow your wallpaper.
#
# fcitx5 selects exactly one theme by name, so this installs one variant under
# the name "crowf". The other variant is still available as crowf-dark /
# crowf-light if you install it separately.
#
# Usage:
#   ./install.sh                 install the dark variant as "crowf"
#   ./install.sh --light         install the light variant instead
#   ./install.sh --matugen       also register the matugen templates
#   ./install.sh --prefix DIR    install under DIR instead of ~/.local/share
#   ./install.sh --uninstall     remove everything this script installed
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}"
THEME_DIR="$PREFIX/fcitx5/themes/crowf"
MATUGEN_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/matugen/config.toml"
MATUGEN_TEMPLATES="${XDG_CONFIG_HOME:-$HOME/.config}/matugen/templates/crowf"

DO_MATUGEN=0
DO_UNINSTALL=0
VARIANT="dark"

while (($#)); do
    case "$1" in
    --matugen) DO_MATUGEN=1 ;;
    --light) VARIANT="light" ;;
    --uninstall) DO_UNINSTALL=1 ;;
    --prefix)
        PREFIX="$2"
        THEME_DIR="$PREFIX/fcitx5/themes/crowf"
        shift
        ;;
    -h | --help)
        sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "unknown option: $1" >&2
        exit 1
        ;;
    esac
    shift
done

info() { printf '  %s\n' "$*"; }
warn() { printf '  warning: %s\n' "$*" >&2; }

need() {
    command -v "$1" >/dev/null || {
        echo "error: $1 is required" >&2
        exit 1
    }
}

if ((DO_UNINSTALL)); then
    echo "Removing crowf-fcitx5"
    rm -rf "$THEME_DIR"
    rm -rf "$MATUGEN_TEMPLATES"
    info "theme removed from $THEME_DIR"
    info "matugen templates removed from $MATUGEN_TEMPLATES"
    if [[ -f $MATUGEN_CONFIG ]]; then
        warn "remove the [templates.crowf*] blocks from $MATUGEN_CONFIG by hand"
    fi
    warn "reset the fcitx5 theme in the config tool if it still points at 'crowf'"
    exit 0
fi

need rsvg-convert

echo "Installing crowf-fcitx5"
mkdir -p "$THEME_DIR"

# The theme ships pre-rendered PNGs so it works without matugen, and so the
# Qt-based candidate window (which cannot decode SVG) gets rounded corners too.
src="$SELF_DIR/themes/crowf-$VARIANT"
if [[ ! -d $src ]]; then
    echo "error: missing $src" >&2
    exit 1
fi
cp "$src/theme.conf" "$THEME_DIR/theme.conf"
info "installed theme.conf ($VARIANT variant)"

for asset in panel highlight; do
    cp "$src/$asset.svg" "$src/$asset.png" "$THEME_DIR/"
    info "installed $asset.svg and $asset.png"
done

info "installed to $THEME_DIR"

if ((DO_MATUGEN)); then
    need matugen
    mkdir -p "$MATUGEN_TEMPLATES"
    cp "$SELF_DIR"/matugen/templates/crowf/* "$MATUGEN_TEMPLATES/"
    info "copied matugen templates to $MATUGEN_TEMPLATES"

    if [[ -f $MATUGEN_CONFIG ]] && grep -q 'templates\.crowf' "$MATUGEN_CONFIG"; then
        info "matugen config already references crowf, leaving it alone"
    else
        cat >>"$MATUGEN_CONFIG" <<EOF

[templates.crowf_theme]
input_path = '$MATUGEN_TEMPLATES/theme.conf'
output_path = '$THEME_DIR/theme.conf'

[templates.crowf_panel]
input_path = '$MATUGEN_TEMPLATES/panel.svg'
output_path = '$THEME_DIR/panel.svg'
post_hook = 'rsvg-convert -w 48 -h 48 $THEME_DIR/panel.svg -o $THEME_DIR/panel.png'

[templates.crowf_highlight]
input_path = '$MATUGEN_TEMPLATES/highlight.svg'
output_path = '$THEME_DIR/highlight.svg'
post_hook = 'rsvg-convert -w 48 -h 48 $THEME_DIR/highlight.svg -o $THEME_DIR/highlight.png'
EOF
        info "appended matugen template entries to $MATUGEN_CONFIG"
    fi
fi

cat <<'EOF'

Next steps:
  1. Restart fcitx5:            fcitx5 -r -d
  2. Pick the theme:            fcitx5-configtool -> Addons -> Classic UI -> Theme = crowf
     or edit ~/.config/fcitx5/conf/classicui.conf:  Theme=crowf
  3. To recolour from a wallpaper:
         matugen image /path/to/wallpaper.jpg -m dark
     (DankMaterialShell and similar tools do this automatically once the
      templates are registered)
EOF
