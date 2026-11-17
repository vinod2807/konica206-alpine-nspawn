# Troubleshooting

## Service will not start

```sh
systemctl status systemd-nspawn@alpine-konica.service -l
journalctl -u systemd-nspawn@alpine-konica.service -b --no-pager
```

Common causes:

- The rootfs or the app binary is missing. The drop-in has
  `ConditionPathExists=/var/lib/machines/alpine-konica/usr/local/bin/konica206-native`;
  a missing binary makes the unit skip rather than loop.
- Port 8001 is already in use. The pinned app fails startup if listeners cannot
  be added. Find the owner with `ss -ltnp | grep 8001` and stop the conflicting
  instance (often the old `konica206uri` app).
- The drop-in was not reloaded after an edit: `systemctl daemon-reload`.

## Log says "Unable to initialize DNS-SD: Daemon not running"

PAPPL tries to register the printer with Avahi at start-up. The Alpine rootfs
intentionally contains no `avahi-daemon`, so this message is expected and
non-fatal: the localhost IPP listener works normally. Only network discovery
advertisement is absent, which is fine for a local CUPS proxy queue.

## USB device not found

```sh
lsusb | grep 132b:232b
udevadm info -a -n /dev/bus/usb/BBB/DDD | grep -E 'idVendor|idProduct'
ipptool -tv ipp://127.0.0.1:8001/ipp/print/konica206 get-printer-attributes.test
```

- Confirm the host udev rule is installed and reloaded:
  `udevadm control --reload && udevadm trigger /sys/bus/usb/devices/...`.
- Inside the machine, check that the device nodes and sysfs subtree exist:
  `machinectl shell alpine-konica /bin/sh -c 'ls -l /dev/bus/usb; ls /sys/bus/usb/devices'`.
- If libusb enumerates nothing, widen **only** the USB sysfs bind in
  `config/nspawn/alpine-konica.nspawn` after verifying it on the target. Do not
  bind all of `/sys` or `/dev` as a shortcut.

## "found 132b:232b but cannot open it" even though the node is visible

The bind mount in `alpine-konica.nspawn` makes the device node visible, but
nspawn's closed device cgroup policy still denies `open()` with `EPERM`. The
service drop-in must also allow the device group:

```
DeviceAllow=char-usb_device rwm
```

`usb_device` is the major-189 group from `/proc/devices`. Wildcards apply to
group names, so `char-189:*` is not valid and silently fails to allow anything.

## "filter not executable: .../245igdirf"

The PAPPL app is falling back to the legacy vendor filter path. Its settings
must be passed to the container with `--setenv=` on the `systemd-nspawn`
command line in the drop-in:

```
--setenv=KONICA_VENDOR_FILTER=/usr/local/lib/konica/konica-native
--setenv=KONICA_PDF_RENDERER=builtin
```

`Environment=` in the host unit does not reach PID 1 inside the container.

## USB interface already claimed

If the log shows a `claim_interface` failure, another process owns interface 1.
The legacy `konica206uri` / Debian-Podman stack and this app cannot print at the
same time. Identify and stop the old service before testing, and remember how to
restore it (see [bootc-integration.md](bootc-integration.md#rollback)).

## Jobs produce no output

`konica-native` fails closed when its halftone screen or ICC profiles are
missing. Check:

```sh
ls -l /var/lib/machines/alpine-konica/usr/local/lib/konica/KonicaMinolta/245igdi/Halftones/
ls -l /var/lib/machines/alpine-konica/usr/local/lib/konica/KonicaMinolta/245igdi/Profiles/
```

Mandatory files: `Halftones/COPA.DEFAULT.600x600.hft`, `Profiles/sRGB.icm`,
`Profiles/sGrayInv.icm`. Re-run the build script with
`KONICA_VENDOR_DATA_DIR` pointing at your legally obtained driver data.

## IPP endpoint answers but CUPS queue fails

- Print to the proxy queue name: `lp -d konica206-ipp file.pdf`. The name
  `konica206` exists only inside PAPPL.
- Check `-m everywhere` was applied with `-E`, otherwise the queue is disabled
  and not accepting jobs (`cupsaccept konica206-ipp` fixes only the second part).
- Remove and recreate the proxy queue while it is idle; see
  [../cups/README.md](../cups/README.md).

## Restart loop

The drop-in limits restarts with `StartLimitIntervalSec=300` and
`StartLimitBurst=5`. If the limit trips:

```sh
systemctl reset-failed systemd-nspawn@alpine-konica.service
systemctl start systemd-nspawn@alpine-konica.service
```

A disconnected printer alone should not cause a loop: PAPPL starts and waits.
A loop usually means the listener could not bind (port conflict) or the app
binary cannot start (missing library — check `ldd` inside the rootfs).

## Health check is unhealthy

```sh
/var/lib/konica206-nspawn/health-check.sh
ipptool -tv ipp://127.0.0.1:8001/ipp/print/konica206 \
  /var/lib/konica206-nspawn/get-printer-attributes.test
```

Install `cups-ipptool` on Fedora for a real check. The `curl` fallback only
proves that the TCP port answers.

## Rebuilding the rootfs safely

```sh
KONICA_FORCE=1 sudo -E scripts/create-alpine-rootfs.sh
# old tree preserved at /var/lib/machines/alpine-konica.bak.<timestamp>
```

Then rebuild dependencies and the app, and re-run the acceptance smoke tests
before switching the service to the new tree.
