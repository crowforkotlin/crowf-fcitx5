#!/usr/bin/env bash
# Publish one tagged release of crowf-fcitx5 to the AUR.
#
# The AUR package is not this repository: it is a separate git repo at
# ssh://aur@aur.archlinux.org/fcitx5-theme-mellow-fixed.git holding exactly two
# files, PKGBUILD and .SRCINFO. AUR rejects a push whose .SRCINFO does not match
# its PKGBUILD, so both are always generated here, never edited by hand.
#
# A tag archive cannot contain its own checksum, so the sha256 that goes to the
# AUR is derived from the published archive at release time. The template in
# this repository keeps the sha256 of the current release; it is never what gets
# published.
#
# Modes:
#   packaging/release.sh 1.1.0              tag v1.1.0 -> AUR 1.1.0-1
#   packaging/release.sh 1.1.0 --pkgrel 2   packaging-only respin -> 1.1.0-2
#   packaging/release.sh 1.1.0 --dry-run    everything except commit/push
#   packaging/release.sh 1.1.0 --prepare DIR
#       write PKGBUILD + .SRCINFO for that tag into DIR; no git, no push
#   packaging/release.sh 1.1.0 --publish-from DIR
#       publish files already prepared (CI builds DIR first, then publishes it)
#
# CI uses --prepare then --publish-from, so the package that is built and
# verified is byte-identical to the package that is published.
#
# Requires: git, curl, sha256sum, makepkg (pacman). The tag must already be
# pushed: the AUR source points at a GitHub tag archive, so publishing before
# the tag exists would produce a package nobody can build.
set -euo pipefail

PKGNAME=fcitx5-theme-mellow-fixed
REPO_SLUG=crowforkotlin/crowf-fcitx5
AUR_URL="${AUR_URL:-ssh://aur@aur.archlinux.org/$PKGNAME.git}"
AUR_BRANCH=master

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SELF_DIR")"

VERSION=""
PKGREL=1
DRY_RUN=0
PREPARE_DIR=""
PUBLISH_FROM=""

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}
note() { printf '  %s\n' "$*"; }

while (($#)); do
    case "$1" in
    --pkgrel)
        PKGREL="${2:-}"
        shift
        ;;
    --dry-run) DRY_RUN=1 ;;
    --prepare)
        PREPARE_DIR="${2:-}"
        shift
        ;;
    --publish-from)
        PUBLISH_FROM="${2:-}"
        shift
        ;;
    -h | --help)
        sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
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

[[ -n $VERSION ]] || die "usage: $0 <version> [--pkgrel N] [--dry-run|--prepare DIR|--publish-from DIR]"
[[ $VERSION =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "not a bare version: $VERSION"
[[ $PKGREL =~ ^[0-9]+$ ]] || die "not a pkgrel: $PKGREL"
[[ -z $PREPARE_DIR || -z $PUBLISH_FROM ]] ||
    die "--prepare and --publish-from are mutually exclusive"

TAG="v$VERSION"

command -v makepkg >/dev/null || die "makepkg not found (pacman)"
command -v curl >/dev/null || die "curl not found"
command -v sha256sum >/dev/null || die "sha256sum not found"

# The git identity for AUR commits: the maintainer, not the repository nickname.
# crowf is only the project/repository name; the person is crowforkotlin.
GIT_NAME="${AUR_GIT_NAME:-crowforkotlin}"
GIT_EMAIL="${AUR_GIT_EMAIL:-crowforkotlin@gmail.com}"
git_commit() {
    git -C "$1" -c user.name="$GIT_NAME" -c user.email="$GIT_EMAIL" \
        commit --quiet -m "$2"
}

# Publish prepared files: commit them on the AUR branch and push. A CI checkout
# and a local AUR clone have unrelated histories, so the incoming branch is
# merged with -s ours --allow-unrelated-histories; the tree that lands is always
# the one in $1, never a rebase of someone else's files.
push_to_aur() {
    local dir="$1" pkgrel
    pkgrel="$(sed -n 's/^[[:space:]]*pkgrel = //p' "$dir/.SRCINFO")"
    [[ $pkgrel =~ ^[0-9]+$ ]] || die "cannot read pkgrel from $dir/.SRCINFO"

    if [[ ! -d $dir/.git ]]; then
        git -C "$dir" init --quiet
        git -C "$dir" checkout --quiet -b "$AUR_BRANCH"
    fi

    git -C "$dir" add PKGBUILD .SRCINFO
    # An earlier run may have committed already, so only commit real changes.
    if ! git -C "$dir" diff --cached --quiet; then
        git_commit "$dir" "upgpkg: $VERSION-$pkgrel"
    fi

    if ! git -C "$dir" remote get-url origin >/dev/null 2>&1; then
        git -C "$dir" remote add origin "$AUR_URL"
    fi
    if git -C "$dir" fetch --quiet origin "$AUR_BRANCH" 2>/dev/null; then
        # Nothing to reconcile when the published tree already matches.
        if git -C "$dir" diff --quiet FETCH_HEAD -- PKGBUILD .SRCINFO; then
            note "AUR already at $VERSION-$pkgrel; nothing to push"
            return 0
        fi
        # Keep the prepared tree: -s ours records the old history as merged
        # while the working tree stays exactly as prepared.
        git -C "$dir" -c user.name="$GIT_NAME" -c user.email="$GIT_EMAIL" \
            merge --quiet --allow-unrelated-histories -s ours \
            --no-edit FETCH_HEAD ||
            die "cannot reconcile with the existing AUR history"
    else
        note "no existing $AUR_BRANCH on the AUR; creating it"
    fi
    git -C "$dir" push --quiet origin "HEAD:$AUR_BRANCH"
    echo "Published $PKGNAME $VERSION-$pkgrel"
}

# --publish-from never downloads or regenerates anything: it publishes the files
# CI already built and verified.
if [[ -n $PUBLISH_FROM ]]; then
    [[ -f $PUBLISH_FROM/PKGBUILD && -f $PUBLISH_FROM/.SRCINFO ]] ||
        die "$PUBLISH_FROM must already contain PKGBUILD and .SRCINFO (see --prepare)"
    grep -q "pkgver = $VERSION" "$PUBLISH_FROM/.SRCINFO" ||
        die "$PUBLISH_FROM/.SRCINFO does not carry pkgver $VERSION"
    if [[ $DRY_RUN == 1 ]]; then
        note "would publish $PUBLISH_FROM as $VERSION"
        exit 0
    fi
    push_to_aur "$PUBLISH_FROM"
    exit 0
fi

# From here on the archive is required: --prepare derives its checksum, and the
# direct mode derives both the checksum and the package files. Downloading the
# tag archive is the real check that the tag is published; probing git refs is
# not, because a CI checkout may be shallow or remote-less.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Fetching $TAG archive"
ARCHIVE="$WORK/$PKGNAME-$VERSION.tar.gz"
URL="https://github.com/$REPO_SLUG/archive/$TAG.tar.gz"
# GitHub can 404 for a few seconds after a new tag, so retry before giving up.
for attempt in 1 2 3 4 5; do
    curl -fsSL -o "$ARCHIVE" "$URL" && break
    [[ $attempt == 5 ]] && die "cannot download $URL; is tag $TAG pushed?"
    note "attempt $attempt failed, retrying"
    sleep $((attempt * 3))
done

# The PKGBUILD extracts into crowf-fcitx5-$pkgver; a differing directory name
# would break package() at build time, not here, so check it now. The listing
# goes to a file first: piping tar into head under pipefail dies on SIGPIPE.
tar tzf "$ARCHIVE" >"$WORK/list"
IFS=/ read -r TOPLEVEL _ <"$WORK/list"
[[ $TOPLEVEL == "crowf-fcitx5-$VERSION" ]] ||
    die "archive top level is $TOPLEVEL, expected crowf-fcitx5-$VERSION"

# GitHub's tag archives carry the tagged PKGBUILD, whose pkgver must agree with
# pkgver= in the generated file, otherwise a build from the tarball would
# declare the wrong version. Read it from the archive rather than via git: a CI
# checkout may not have the tag as a ref at all.
TAGGED_PKGVER="$(tar xzOf "$ARCHIVE" "crowf-fcitx5-$VERSION/packaging/PKGBUILD" 2>/dev/null |
    sed -n 's/^pkgver=//p' || true)"
[[ $TAGGED_PKGVER == "$VERSION" ]] ||
    die "$TAG ships pkgver=${TAGGED_PKGVER:-<none>}, expected $VERSION"

SHA="$(sha256sum "$ARCHIVE" | cut -d' ' -f1)"
note "sha256 $SHA"

emit() {
    local dir="$1"
    mkdir -p "$dir"
    sed -e "s/^pkgver=.*/pkgver=$VERSION/" \
        -e "s/^pkgrel=.*/pkgrel=$PKGREL/" \
        -e "s/^sha256sums=.*/sha256sums=('$SHA')/" \
        "$SELF_DIR/PKGBUILD" >"$dir/PKGBUILD"
    # .SRCINFO is generated from the PKGBUILD; AUR compares the two on push.
    (cd "$dir" && makepkg --printsrcinfo >.SRCINFO) ||
        die "makepkg --printsrcinfo failed"
    [[ -s $dir/.SRCINFO ]] || die ".SRCINFO is empty"
    grep -q "pkgver = $VERSION" "$dir/.SRCINFO" ||
        die ".SRCINFO does not carry pkgver $VERSION"
    grep -q "pkgrel = $PKGREL" "$dir/.SRCINFO" ||
        die ".SRCINFO does not carry pkgrel $PKGREL"
}

if [[ -n $PREPARE_DIR ]]; then
    emit "$PREPARE_DIR"
    note "wrote $PREPARE_DIR/PKGBUILD and .SRCINFO"
    exit 0
fi

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
        git_commit "$AUR_DIR" "seed"
    else
        echo "Cloning $AUR_URL"
        git clone --quiet "$AUR_URL" "$AUR_DIR" ||
            die "clone failed; the AUR repo must exist before it can be updated"
    fi
else
    echo "Updating $AUR_DIR"
    git -C "$AUR_DIR" fetch --quiet origin ||
        die "cannot fetch from the AUR remote in $AUR_DIR"
    # Discard leftovers from an interrupted earlier run.
    git -C "$AUR_DIR" reset --quiet --hard "@{upstream}" ||
        die "cannot reset $AUR_DIR to @{upstream}"
fi

emit "$AUR_DIR"

# Stage first, then ask git whether anything actually changed: this works for a
# real clone and a scratch repo alike, and re-running a version becomes a no-op
# instead of an empty commit.
git -C "$AUR_DIR" add PKGBUILD .SRCINFO
if git -C "$AUR_DIR" diff --cached --quiet; then
    note "AUR already at $VERSION-$PKGREL; nothing to push"
    exit 0
fi

git -C "$AUR_DIR" diff --cached --stat -- PKGBUILD .SRCINFO | sed 's/^/  /'

if [[ $DRY_RUN == 1 ]]; then
    git -C "$AUR_DIR" diff --cached -- PKGBUILD .SRCINFO | sed 's/^/  /'
    echo "Dry run: not committing or pushing"
    exit 0
fi

git_commit "$AUR_DIR" "upgpkg: $VERSION-$PKGREL"
git -C "$AUR_DIR" push --quiet origin "HEAD:$AUR_BRANCH"
echo "Published $PKGNAME $VERSION-$PKGREL"
