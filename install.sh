#!/usr/bin/env bash
# crowf-fcitx5 — fcitx5 candidate panel themes that survive every toolkit.
#
# Installs the ten vendored Mellow colour schemes. Each one ships pre-rendered
# PNG textures alongside the editable SVG, because the panels that render the
# candidate list are not all the same program:
#
#   classicui            decodes SVG and PNG.
#   client-side panels   (Qt/GTK apps ask for these over D-Bus) read the colour
#                        keys in theme.conf and the PNG. WeChat draws its own
#                        with statically linked Qt 5.15, which loads no
#                        imageformat plugins at all — SVG is simply not an
#                        option there, and without a PNG the panel degrades to
#                        a flat square with hard corners.
#
# The upstream Mellow themes are SVG-only and declare a
# HighlightBackgroundColor that does not match their own highlight texture, so
# classicui and the client panels paint different fills for the selected
# candidate. Both are corrected in themes/.
#
# Usage:
#   ./install.sh                install every vendored theme
#   ./install.sh --theme NAME   install only one (repeatable)
#   ./install.sh --prefix DIR   install under DIR instead of ~/.local/share
#   ./install.sh --check        audit installed themes, change nothing
#   ./install.sh --uninstall    remove the themes this script installed
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}"
THEMES_DIR="$PREFIX/fcitx5/themes"
VENDOR_DIR="$SELF_DIR/themes"

DO_UNINSTALL=0
DO_CHECK=0
SELECTED=()

info() { printf '  %s\n' "$*"; }
warn() { printf '  warning: %s\n' "$*" >&2; }

usage() { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; }

while (($#)); do
    case "$1" in
    --theme)
        SELECTED+=("$2")
        shift
        ;;
    --prefix)
        PREFIX="$2"
        THEMES_DIR="$PREFIX/fcitx5/themes"
        shift
        ;;
    --uninstall) DO_UNINSTALL=1 ;;
    --check) DO_CHECK=1 ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "unknown option: $1" >&2
        exit 1
        ;;
    esac
    shift
done

# Every theme this repository owns, in the order they will be installed.
all_themes() {
    local dir
    for dir in "$VENDOR_DIR"/mellow-*/; do
        [[ -d $dir ]] && basename "$dir"
    done
}

if ((DO_UNINSTALL)); then
    echo "Removing crowf-fcitx5 themes"
    for name in $(all_themes); do
        rm -rf "${THEMES_DIR:?}/$name"
        info "removed $name"
    done
    exit 0
fi

if ((DO_CHECK)); then
    python3 "$SELF_DIR/tools/fix-contrast.py" --check "$THEMES_DIR"/mellow-* 2>/dev/null ||
        true
    exit 0
fi

if ((${#SELECTED[@]})); then
    themes=("${SELECTED[@]}")
else
    mapfile -t themes < <(all_themes)
fi

if ((${#themes[@]} == 0)); then
    echo "error: $VENDOR_DIR contains no themes" >&2
    exit 1
fi

echo "Installing crowf-fcitx5"
mkdir -p "$THEMES_DIR"

installed=0
for name in "${themes[@]}"; do
    src="$VENDOR_DIR/$name"
    if [[ ! -d $src ]]; then
        warn "skip $name (not in $VENDOR_DIR)"
        continue
    fi
    dest="$THEMES_DIR/$name"
    mkdir -p "$dest"
    cp "$src/panel.svg" "$src/panel.png" \
       "$src/highlight.svg" "$src/highlight.png" \
       "$src/theme.conf" "$dest/"
    info "installed $name"
    installed=$((installed + 1))
done

echo
info "$installed theme(s) installed to $THEMES_DIR"

# Colour regressions are the whole reason this repository exists; make sure the
# installed copies still pass rather than trusting that the vendored files do.
if command -v python3 >/dev/null; then
    echo
    echo "Auditing installed themes"
    python3 "$SELF_DIR/tools/fix-contrast.py" --check "$THEMES_DIR"/mellow-* || true
fi

cat <<'EOF'

Next steps:
  Pick a theme in the fcitx5 configuration tool, or set it directly:

    Theme=<name>          in ~/.config/fcitx5/conf/classicui.conf
    DarkTheme=<name>      for the variant used when the desktop is dark

  Variants that share a colour family differ only in panel brightness, so pair
  a base name with its -dark sibling, e.g. Theme=mellow-graphite-dark.
EOF
