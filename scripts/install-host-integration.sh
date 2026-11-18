#!/bin/sh
# Install the host-side (Fedora) integration: nspawn machine config, systemd
# drop-in, udev rule and health check. Does NOT touch Fedora CUPS, the existing
# printer services, or any host packages/layers.
#
#   sudo scripts/install-host-integration.sh
#   IPP_PORT=8002 sudo -E scripts/install-host-integration.sh   # side-by-side
#   KONICA_START=1 sudo -E scripts/install-host-integration.sh  # also start now
#
# The port is configurable so this can run alongside an existing PAPPL app.
# Nothing is written under /usr: this is bootc-safe with no rpm-ostree overlay,
# no package layering and no new bootc deployment (all state lives in /var and
# /etc, which are already-writable persistent directories on a bootc host).
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
HELPER_DIR=/var/lib/konica206-nspawn

say "installing nspawn machine configuration"
install -D -m 644 "$HERE/config/nspawn/$MACHINE_NAME.nspawn" "/etc/systemd/nspawn/$MACHINE_NAME.nspawn"

say "installing systemd-nspawn drop-in (port $IPP_PORT)"
mkdir -p "/etc/systemd/system/$UNIT.d"
sed "s|@IPP_PORT@|$IPP_PORT|g" \
    "$HERE/config/systemd/$UNIT.d/override.conf" > "/etc/systemd/system/$UNIT.d/override.conf"
chmod 644 "/etc/systemd/system/$UNIT.d/override.conf"

say "installing USB udev rule"
# Use a distinct filename: the bootc image already ships 70-konica206.rules
# which triggers queue setup units. A same-named file here would shadow it.
install -D -m 644 "$HERE/udev/70-konica206.rules" /etc/udev/rules.d/75-konica206-nspawn.rules
udevadm control --reload || true

say "installing health check under /var (bootc-safe, no /usr writes)"
install -D -m 755 "$HERE/scripts/health-check.sh" "$HELPER_DIR/health-check.sh"
# systemd runs as init_t, which may not execute a script that inherits the
# var_lib_t label from /var/lib (avc: denied { execute } -> status=203/EXEC).
# Label it bin_t and persist the rule so it survives a full filesystem relabel.
if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
    if command -v semanage >/dev/null 2>&1; then
        semanage fcontext -a -t bin_t "$HELPER_DIR/health-check.sh" 2>/dev/null || \
            semanage fcontext -m -t bin_t "$HELPER_DIR/health-check.sh" || true
    fi
    if command -v restorecon >/dev/null 2>&1; then
        restorecon -v "$HELPER_DIR/health-check.sh" || true
    fi
fi
install -D -m 644 "$HERE/config/ipp/get-printer-attributes.test" "$HELPER_DIR/get-printer-attributes.test"
printf '%s\n' "$IPP_PORT" > "$HELPER_DIR/port"
chmod 644 "$HELPER_DIR/port"
mkdir -p /etc/systemd/system
sed "s|@IPP_PORT@|$IPP_PORT|g" \
    "$HERE/systemd/konica206-healthcheck.service" > /etc/systemd/system/konica206-healthcheck.service
install -D -m 644 "$HERE/systemd/konica206-healthcheck.timer" /etc/systemd/system/konica206-healthcheck.timer
chmod 644 /etc/systemd/system/konica206-healthcheck.service /etc/systemd/system/konica206-healthcheck.timer

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
echo "Health:    $HELPER_DIR/health-check.sh (or systemctl status konica206-healthcheck.service)"
echo "Rollback:  sudo scripts/remove-host-integration.sh"
echo
echo "No rpm-ostree overlay, package layering or bootc deployment was created."
echo "The service is enabled but not started. Start it only after reading"
echo "docs/testing-and-acceptance.md; existing printer services are untouched."
