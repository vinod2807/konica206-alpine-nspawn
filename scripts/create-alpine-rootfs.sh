#!/bin/sh
# Create the pinned Alpine root filesystem used by systemd-nspawn.
#
#   sudo scripts/create-alpine-rootfs.sh
#   KONICA_FORCE=1 sudo -E scripts/create-alpine-rootfs.sh   # replace existing
#
# Host-side only. This script does not install or change any host service; it
# only downloads a verified minirootfs and extracts it to $ROOTFS. An existing
# rootfs is never deleted: with KONICA_FORCE=1 it is moved to a timestamped
# .bak directory first, so rollback stays one rename away.
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
. "$HERE/config/pins.env"

say() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "run as root"; }

need_root

TARBALL_NAME="alpine-minirootfs-$ALPINE_VERSION-$ALPINE_ARCH.tar.gz"
TARBALL="$CACHE_DIR/$TARBALL_NAME"
URL="$ALPINE_BASEURL/v$ALPINE_VERSION/releases/$ALPINE_ARCH/$TARBALL_NAME"

mkdir -p "$CACHE_DIR"
if [ ! -f "$TARBALL" ]; then
    say "downloading $URL"
    curl -fSL --retry 3 -o "$TARBALL" "$URL"
else
    say "using cached $TARBALL"
fi

say "verifying SHA256"
ACTUAL=$(sha256sum "$TARBALL" | awk '{print $1}')
if [ "$ACTUAL" != "$ALPINE_MINIROOTFS_SHA256" ]; then
    die "checksum mismatch: expected $ALPINE_MINIROOTFS_SHA256, got $ACTUAL"
fi

if [ -e "$ROOTFS" ]; then
    [ "${KONICA_FORCE:-0}" = 1 ] || die "$ROOTFS exists; set KONICA_FORCE=1 to replace it (a .bak snapshot is kept)"
    BACKUP="$ROOTFS.bak.$(date -u +%Y%m%dT%H%M%SZ)"
    say "moving existing rootfs to $BACKUP"
    mv "$ROOTFS" "$BACKUP"
fi

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/konica-rootfs.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT HUP INT TERM

say "extracting minirootfs into $STAGE"
tar -xzf "$TARBALL" -C "$STAGE"

# Keep apk on the same release as the minirootfs instead of tracking a moving
# 'latest' tree. This is what makes later installs reproducible.
mkdir -p "$STAGE/etc/apk"
cat > "$STAGE/etc/apk/repositories" <<EOF
$ALPINE_BASEURL/v$ALPINE_VERSION/main
$ALPINE_BASEURL/v$ALPINE_VERSION/community
EOF

printf '%s\n' "$MACHINE_NAME" > "$STAGE/etc/hostname"

say "installing rootfs to $ROOTFS"
mkdir -p "$(dirname "$ROOTFS")"
mv "$STAGE" "$ROOTFS"
trap - EXIT HUP INT TERM

say "done"
du -sh "$ROOTFS"
echo "Next: sudo scripts/install-alpine-dependencies.sh"
