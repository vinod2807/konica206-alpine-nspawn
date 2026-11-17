#!/bin/sh
# Build PAPPL, konica-native (renderer) and konica206-native (PAPPL app) from
# pinned sources, install them into the Alpine rootfs, then remove the build
# toolchain.
#
#   sudo scripts/build-and-install-printer-app.sh
#   KONICA_VENDOR_DATA_DIR=/path/to/245igdi sudo -E scripts/build-and-install-printer-app.sh
#
# Proprietary Konica runtime data is NEVER downloaded by this project. If
# KONICA_VENDOR_DATA_DIR is set it must contain a copy of the 245igdi Halftones/
# and Profiles/ directories, supplied by you from a legally obtained driver.
# See docs/security.md and docs/upstream-pins.md for the redistribution decision.
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
. "$HERE/config/pins.env"

say() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "run as root"; }

need_root
[ -d "$ROOTFS" ] || die "rootfs missing: $ROOTFS (run scripts/create-alpine-rootfs.sh first)"

CACHE="$CACHE_DIR/sources"
BUILD=/tmp/konica206-build
VENDOR=${KONICA_VENDOR_DATA_DIR:-}
mkdir -p "$CACHE"

fetch_pinned() {
    fname=$1
    repo=$2
    rev=$3
    target="$CACHE/$fname"
    if [ ! -d "$target/.git" ]; then
        say "fetching $fname from $repo"
        git clone -q "$repo" "$target"
    fi
    say "pinning $fname to $rev"
    git -C "$target" checkout -q "$rev"
}

fetch_pinned pappl https://github.com/michaelrsweet/pappl.git "$PAPPL_COMMIT"
fetch_pinned konica-native-musl https://github.com/vinod2807/konica-native-musl.git "$KONICA_NATIVE_MUSL_COMMIT"
fetch_pinned konica206-native-alpine https://github.com/vinod2807/konica206-native-alpine.git "$KONICA206_NATIVE_ALPINE_COMMIT"

if [ -n "$VENDOR" ]; then
    for f in Halftones/COPA.DEFAULT.600x600.hft Profiles/sRGB.icm Profiles/sGrayInv.icm; do
        [ -r "$VENDOR/$f" ] || die "proprietary runtime file missing: $VENDOR/$f"
    done
else
    say "WARNING: KONICA_VENDOR_DATA_DIR is not set"
    say "         the IPP stack installs and tests fine, but real printing requires"
    say "         the manual runtime-data step documented in docs/security.md"
fi

say "copying pinned sources into the rootfs"
chroot "$ROOTFS" /bin/sh -c "rm -rf $BUILD && mkdir -p $BUILD"
for n in pappl konica-native-musl konica206-native-alpine; do
    cp -a "$CACHE/$n" "$ROOTFS$BUILD/$n"
done

say "installing temporary build dependencies"
chroot "$ROOTFS" apk add --no-cache --virtual .konica-build \
    build-base pkgconf cups-dev libusb-dev libpng-dev libjpeg-turbo-dev \
    zlib-dev openssl-dev avahi-dev python3

say "building PAPPL $PAPPL_VERSION"
chroot "$ROOTFS" /bin/sh -c "cd $BUILD/pappl && ./configure --prefix=/usr/local >/dev/null && make -j\$(nproc) >/dev/null && make install >/dev/null"
chroot "$ROOTFS" /bin/sh -c 'grep -qxF /usr/local/lib /etc/ld.so.conf || echo /usr/local/lib >> /etc/ld.so.conf; ldconfig'

say "building and testing konica-native (vendor-stage renderer)"
chroot "$ROOTFS" /bin/sh -c "cd $BUILD/konica-native-musl && make CC=cc >/dev/null && make check && install -D -m755 konica-native /usr/local/lib/konica/konica-native"

say "building and testing konica206-native (PAPPL application)"
chroot "$ROOTFS" /bin/sh -c "PKG_CONFIG_PATH=/usr/local/lib/pkgconfig make -C $BUILD/konica206-native-alpine >/dev/null && PKG_CONFIG_PATH=/usr/local/lib/pkgconfig make -C $BUILD/konica206-native-alpine check && PKG_CONFIG_PATH=/usr/local/lib/pkgconfig make -C $BUILD/konica206-native-alpine install >/dev/null"

if [ -n "$VENDOR" ]; then
    say "installing the proprietary runtime data you supplied"
    mkdir -p "$ROOTFS/usr/local/lib/konica/KonicaMinolta/245igdi"
    cp -a "$VENDOR/." "$ROOTFS/usr/local/lib/konica/KonicaMinolta/245igdi/"
    say "running the real-renderer end-to-end test"
    chroot "$ROOTFS" /bin/sh -c "cd $BUILD/konica206-native-alpine && NATIVE=/usr/local/lib/konica/konica-native make check-native"
else
    say "skipping real-renderer test: no proprietary runtime data supplied"
fi

say "removing temporary build dependencies"
chroot "$ROOTFS" apk del .konica-build
chroot "$ROOTFS" /bin/sh -c "rm -rf $BUILD; ldconfig"

say "verifying dynamic library dependencies"
chroot "$ROOTFS" /bin/sh -c 'ldd /usr/local/bin/konica206-native; echo ---; ldd /usr/local/lib/konica/konica-native'

say "writing install manifest"
mkdir -p "$ROOTFS/usr/local/share/konica206"
{
    echo "Generated (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Alpine:          $ALPINE_VERSION ($ALPINE_ARCH)"
    echo "PAPPL:           $PAPPL_VERSION ($PAPPL_COMMIT)"
    echo "Renderer:        konica-native-musl ($KONICA_NATIVE_MUSL_COMMIT)"
    echo "Application:     konica206-native-alpine ($KONICA206_NATIVE_ALPINE_COMMIT)"
    echo "Proprietary data: ${VENDOR:-NOT INSTALLED - manual step required}"
    echo
    echo "Installed paths:"
    echo "  /usr/local/bin/konica206-native"
    echo "  /usr/local/bin/konica-send"
    echo "  /usr/local/bin/konica-render"
    echo "  /usr/local/lib/konica/konica-native"
    echo "  /usr/local/lib/libpappl.so.1"
    echo "  /usr/local/lib/konica/KonicaMinolta/245igdi/  (only if supplied)"
} > "$ROOTFS/usr/local/share/konica206/INSTALL_MANIFEST.txt"

say "done"
chroot "$ROOTFS" /bin/sh -c 'du -sh /usr/local/lib /usr/local/bin 2>/dev/null || true'
echo "Next: review docs/testing-and-acceptance.md, then scripts/install-host-integration.sh"
