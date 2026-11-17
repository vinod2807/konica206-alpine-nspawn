#!/bin/sh
# Install the host-side (Fedora) integration: nspawn machine config, systemd
# drop-in, udev rule and health check. Does NOT touch Fedora CUPS, the existing
# Debian/Podman setup, or the printer's legacy queue.
#
#   sudo scripts/install-host-integration.sh
#   KONICA_START=1 sudo -E scripts/install-host-integration.sh   # also start now
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
. "$HERE/config/pins.env"

say() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "run as root"; }

need_root
[ -d "$ROOTFS" ] || die "rootfs missing: $ROOTFS (build it first)"

UNIT="systemd-nspawn@$MACHINE_NAME.service"

say "installing nspawn machine configuration"
install -D -m 644 "$HERE/config/nspawn/$MACHINE_NAME.nspawn" "/etc/systemd/nspawn/$MACHINE_NAME.nspawn"

say "installing systemd-nspawn drop-in"
install -D -m 644 "$HERE/config/systemd/$UNIT.d/override.conf" "/etc/systemd/system/$UNIT.d/override.conf"

say "installing USB udev rule"
install -D -m 644 "$HERE/udev/70-konica206.rules" /etc/udev/rules.d/70-konica206.rules
udevadm control --reload || true

say "installing health check"
install -D -m 755 "$HERE/scripts/health-check.sh" /usr/local/lib/konica206/health-check.sh
install -D -m 644 "$HERE/config/ipp/get-printer-attributes.test" /usr/local/lib/konica206/get-printer-attributes.test
install -D -m 644 "$HERE/systemd/konica206-healthcheck.service" /etc/systemd/system/konica206-healthcheck.service
install -D -m 644 "$HERE/systemd/konica206-healthcheck.timer" /etc/systemd/system/konica206-healthcheck.timer

say "reloading systemd and enabling units (not starting by default)"
systemctl daemon-reload
systemctl enable "$UNIT" konica206-healthcheck.timer

if [ "${KONICA_START:-0}" = 1 ]; then
    say "starting $UNIT as requested"
    systemctl start "$UNIT"
fi

say "done"
echo "Status:    systemctl status $UNIT"
echo "IPP:       ipp://127.0.0.1:$IPP_PORT/ipp/print/konica206"
echo "Health:    systemctl status konica206-healthcheck.service"
echo "Rollback:  sudo scripts/remove-host-integration.sh"
echo
echo "The service is enabled but not started. Start it only after reading"
echo "docs/testing-and-acceptance.md; the old Debian/Podman path stays available."
