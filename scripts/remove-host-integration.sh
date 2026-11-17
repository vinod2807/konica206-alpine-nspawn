#!/bin/sh
# Remove the host-side integration installed by install-host-integration.sh.
#
#   sudo scripts/remove-host-integration.sh
#   KONICA_REMOVE_ROOTFS=1 sudo -E scripts/remove-host-integration.sh
#
# This does NOT remove the old Debian/Podman setup or any Fedora CUPS queue.
# By default the Alpine rootfs is left in place. With KONICA_REMOVE_ROOTFS=1
# it is moved aside to a timestamped .disabled directory (not deleted).
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
. "$HERE/config/pins.env"

say() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "run as root"; }

need_root

UNIT="systemd-nspawn@$MACHINE_NAME.service"

say "stopping and disabling units"
systemctl disable --now "$UNIT" konica206-healthcheck.timer konica206-healthcheck.service 2>/dev/null || true
systemctl stop konica206-healthcheck.service 2>/dev/null || true

say "removing host files"
rm -f "/etc/systemd/nspawn/$MACHINE_NAME.nspawn"
rm -f "/etc/systemd/system/$UNIT.d/override.conf"
rmdir "/etc/systemd/system/$UNIT.d" 2>/dev/null || true
rm -f /etc/udev/rules.d/70-konica206.rules
rm -f /etc/systemd/system/konica206-healthcheck.service
rm -f /etc/systemd/system/konica206-healthcheck.timer
rm -rf /usr/local/lib/konica206

if [ "${KONICA_REMOVE_ROOTFS:-0}" = 1 ] && [ -e "$ROOTFS" ]; then
    DISABLED="$ROOTFS.disabled.$(date -u +%Y%m%dT%H%M%SZ)"
    say "moving rootfs aside to $DISABLED"
    mv "$ROOTFS" "$DISABLED"
fi

say "reloading systemd and udev"
systemctl daemon-reload
udevadm control --reload || true

say "done"
echo "The old Debian/Podman printer service and any CUPS proxy queue were untouched."
