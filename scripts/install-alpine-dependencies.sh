#!/bin/sh
# Install the RUNTIME packages into the Alpine rootfs.
#
# Build tooling is deliberately NOT installed here; it is added temporarily by
# scripts/build-and-install-printer-app.sh and removed again after the build.
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
. "$HERE/config/pins.env"

say() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "run as root"; }

need_root
[ -d "$ROOTFS" ] || die "rootfs missing: $ROOTFS (run scripts/create-alpine-rootfs.sh first)"

say "refreshing apk index"
chroot "$ROOTFS" /bin/sh -c 'apk update'

say "installing runtime packages"
# cups-libs: libcups/libcupsimage used by the PAPPL app
# libusb:    USB transport
# ghostscript: 'builtin' PDF renderer (upstream unit default)
# cups-filters: provides pdftoraster for the 'system' renderer mode; not a
#               full cupsd and not the legacy cups-filters 1.28 chain on Fedora
# python3:   used by the renderer's vendor-free test suite
chroot "$ROOTFS" /bin/sh -c 'apk add --no-cache cups-libs libusb ghostscript cups-filters python3 ca-certificates tzdata'

say "configuring the dynamic linker for /usr/local (PAPPL is built from source)"
chroot "$ROOTFS" /bin/sh -c 'grep -qxF /usr/local/lib /etc/ld.so.conf || echo /usr/local/lib >> /etc/ld.so.conf; ldconfig'

say "installed package footprint"
chroot "$ROOTFS" /bin/sh -c 'apk info | sort'

say "done"
echo "Next: sudo scripts/build-and-install-printer-app.sh"
