#!/bin/sh
# Remove the host-side integration installed by install-host-integration.sh.
#
#   sudo scripts/remove-host-integration.sh
#   KONICA_REMOVE_ROOTFS=1 sudo -E scripts/remove-host-integration.sh
#
# This does NOT remove any existing printer service, CUPS queue, package layer
# or bootc deployment. By default the Alpine rootfs is left in place. With
# KONICA_REMOVE_ROOTFS=1 it is moved aside to a timestamped .disabled directory.
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
rm -f /etc/udev/rules.d/75-konica206-nspawn.rules
rm -f /etc/systemd/system/konica206-healthcheck.service
rm -f /etc/systemd/system/konica206-healthcheck.timer
rm -rf /var/lib/konica206-nspawn

if [ "${KONICA_REMOVE_ROOTFS:-0}" = 1 ] && [ -e "$ROOTFS" ]; then
    DISABLED="$ROOTFS.disabled.$(date -u +%Y%m%dT%H%M%SZ)"
    say "moving rootfs aside to $DISABLED"
    mv "$ROOTFS" "$DISABLED"
fi

say "reloading systemd and udev"
systemctl daemon-reload
udevadm control --reload || true

say "done"
echo "Existing printer services, CUPS queues and package layers were untouched."
