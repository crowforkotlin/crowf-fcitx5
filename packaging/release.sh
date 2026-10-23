#!/usr/bin/env bash
# Publish one tagged release of crowf-fcitx5 to the AUR.
#
# The AUR package is not this repository: it is a separate git repo at
# ssh://aur@aur.archlinux.org/fcitx5-theme-mellow-fixed.git holding exactly two
# files, PKGBUILD and .SRCINFO. AUR rejects a push whose .SRCINFO does not match
# its PKGBUILD, so both are regenerated here, never edited by hand.
#
# Usage:
#   packaging/release.sh 1.1.0             tag v1.1.0 -> AUR 1.1.0-1
#   packaging/release.sh 1.1.0 --pkgrel 2  packaging-only respin -> 1.1.0-2
#   packaging/release.sh 1.1.0 --dry-run   do everything except commit/push
#
# Requirements: git, curl, sha256sum, makepkg (pacman). The tag must already be
# pushed: the AUR source points at a GitHub tag archive, so publishing before
# the tag exists would produce a package nobody can build.
set -euo pipefail

PKGNAME=fcitx5-theme-mellow-fixed
REPO_SLUG=crowforkotlin/crowf-fcitx5
AUR_URL="ssh://aur@aur.archlinux.org/$PKGNAME.git"

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SELF_DIR")"

VERSION=""
PKGREL=1
DRY_RUN=0

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}
note() { printf '  %s\n' "$*"; }

while (($#)); do
    case "$1" in
    --pkgrel)
        PKGREL="$2"
        shift
        ;;
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
        sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    -*)
        die "unknown option: $1"
        ;;
    *)
        [[ -z $VERSION ]] || die "version given twice"
        VERSION="$1"
        ;;
    esac
    shift
done

[[ -n $VERSION ]] || die "usage: $0 <version> [--pkgrel N] [--dry-run]"
[[ $VERSION =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "not a bare version: $VERSION"
[[ $PKGREL =~ ^[0-9]+$ ]] || die "not a pkgrel: $PKGREL"

TAG="v$VERSION"

command -v makepkg >/dev/null || die "makepkg not found (pacman)"
command -v curl >/dev/null || die "curl not found"

# The tag is the source of truth: the archive must exist before the AUR copy
# can point at it. A CI checkout may hold the tag only as a detached commit, so
# accept either the local ref or the remote one.
has_tag() {
    git -C "$ROOT_DIR" rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 && return 0
    git -C "$ROOT_DIR" ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1
}
if [[ $DRY_RUN == 0 ]]; then
    has_tag || die "tag $TAG is not published; tag and push the release first"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Fetching $TAG archive"
ARCHIVE="$WORK/$PKGNAME-$VERSION.tar.gz"
URL="https://github.com/$REPO_SLUG/archive/$TAG.tar.gz"
if ! curl -fsSL -o "$ARCHIVE" "$URL"; then
    die "cannot download $URL (GitHub can 404 for a few seconds after a new tag)"
fi

# The PKGBUILD extracts into crowf-fcitx5-$pkgver; a differing directory name
# would break package() at build time, not here, so check it now. The listing
# goes to a file first: piping tar into head under pipefail dies on SIGPIPE.
tar tzf "$ARCHIVE" >"$WORK/list"
IFS=/ read -r TOPLEVEL _ <"$WORK/list"
[[ $TOPLEVEL == "crowf-fcitx5-$VERSION" ]] ||
    die "archive top level is $TOPLEVEL, expected crowf-fcitx5-$VERSION"

SHA="$(sha256sum "$ARCHIVE" | cut -d' ' -f1)"
note "sha256 $SHA"

AUR_DIR="${AUR_DIR:-$HOME/aur/$PKGNAME}"

# A dry run on a machine without an AUR clone uses a scratch repo seeded from
# the current package files, so the diff is still realistic.
if [[ ! -d $AUR_DIR/.git ]]; then
    if [[ $DRY_RUN == 1 ]]; then
        AUR_DIR="$WORK/aur"
        mkdir -p "$AUR_DIR"
        git -C "$AUR_DIR" init --quiet
        sed -e "s/^pkgver=.*/pkgver=0.0.0/" "$SELF_DIR/PKGBUILD" >"$AUR_DIR/PKGBUILD"
        (cd "$AUR_DIR" && makepkg --printsrcinfo >.SRCINFO)
        git -C "$AUR_DIR" add PKGBUILD .SRCINFO
        git -C "$AUR_DIR" -c user.name=release -c user.email=release@local \
            commit --quiet -m "seed"
    else
        echo "Cloning $AUR_URL"
        git clone --quiet "$AUR_URL" "$AUR_DIR" ||
            die "clone failed; the AUR repo must exist before it can be updated"
    fi
else
    echo "Updating $AUR_DIR"
    git -C "$AUR_DIR" fetch --quiet origin ||
        die "cannot fetch from the AUR remote in $AUR_DIR"
    # Discard local edits from an interrupted earlier run.
    git -C "$AUR_DIR" reset --quiet --hard '@{upstream}' ||
        die "cannot reset $AUR_DIR to its upstream branch"
fi

echo "Writing PKGBUILD $VERSION-$PKGREL"
sed -e "s/^pkgver=.*/pkgver=$VERSION/" \
    -e "s/^pkgrel=.*/pkgrel=$PKGREL/" \
    -e "s/^sha256sums=.*/sha256sums=('$SHA')/" \
    "$SELF_DIR/PKGBUILD" >"$AUR_DIR/PKGBUILD"

# .SRCINFO is generated from the PKGBUILD, never hand-edited; AUR compares them.
(cd "$AUR_DIR" && makepkg --printsrcinfo >.SRCINFO) ||
    die "makepkg --printsrcinfo failed"

if [[ ! -s $AUR_DIR/.SRCINFO ]]; then
    die ".SRCINFO is empty"
fi
grep -q "pkgver = $VERSION" "$AUR_DIR/.SRCINFO" ||
    die ".SRCINFO does not carry pkgver $VERSION"

if git -C "$AUR_DIR" diff --quiet -- PKGBUILD .SRCINFO; then
    note "AUR already at $VERSION-$PKGREL; nothing to push"
    exit 0
fi

git -C "$AUR_DIR" diff --stat -- PKGBUILD .SRCINFO | sed 's/^/  /'

if [[ $DRY_RUN == 1 ]]; then
    echo "Dry run: not committing or pushing"
    git -C "$AUR_DIR" diff -- PKGBUILD .SRCINFO | sed 's/^/  /'
    exit 0
fi

git -C "$AUR_DIR" add PKGBUILD .SRCINFO
git -C "$AUR_DIR" commit --quiet -m "upgpkg: $VERSION-$PKGREL"
git -C "$AUR_DIR" push --quiet origin HEAD:master
echo "Published $PKGNAME $VERSION-$PKGREL"
