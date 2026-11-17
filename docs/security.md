# Security decisions

## Network exposure

- PAPPL is started with `-o listen=localhost`. The IPP endpoint and the PAPPL
  web interface both bind to the loopback interface only.
- The PAPPL web interface has **no authentication**. It must never be exposed
  to an untrusted LAN. `config/nspawn/alpine-konica.nspawn` sets `Private=no`
  and `VirtualEthernet=no` so the container shares the host network namespace;
  this is required for the CUPS proxy at `127.0.0.1:8001`, and it also means
  "localhost" is genuinely host-local.
- Do not change `listen=any` unless you have (a) restricted access to the
  listener with host firewall rules and (b) accepted that the admin interface
  is unauthenticated.

## Privileges and devices

- No `--privileged` and no user namespace. The container runs the PAPPL app as
  root because it must claim a USB interface, but the bind mounts are narrowly
  scoped:
  - `/dev/bus/usb` — the USB device tree (the printer is `132b:232b`).
  - `/sys/bus/usb/devices` — read-only, for libusb enumeration.
- The host is not shared wholesale: no bind of the entire `/dev`, `/proc` or
  `/sys`. systemd-nspawn still creates its own minimal `/dev`, `/proc` and
  `/sys` inside the machine.
- The host-side udev rule grants `GROUP=lp`, `MODE=0660` and `uaccess` for the
  printer. Permissions survive unplug/replug because they are applied by udev
  on every device add event.
- Only one process may own USB interface 1. The legacy Debian/Podman stack must
  be stopped before this service prints; see
  [troubleshooting.md](troubleshooting.md#usb-interface-already-claimed).

## Proprietary Konica runtime data

The halftone screen (`COPA.DEFAULT.600x600.hft`) and the ICC profiles
(`sRGB.icm`, `sGrayInv.icm`) are Konica Minolta's files. The upstream project
states that redistribution requires the vendor's permission.

Decision for this repository:

- No proprietary file is committed, generated, downloaded or embedded in any
  image built from this repository.
- The build script only copies such files when the operator explicitly sets
  `KONICA_VENDOR_DATA_DIR` to a local directory they supplied, and it checks
  for the three mandatory files first.
- A rootfs built without them is fully functional for the IPP path and for all
  vendor-free tests, but jobs will abort with no output until the data is
  installed. This is the intended fail-closed behaviour of `konica-native`.

Manual install (on the target):

```sh
# Directory layout expected under KONICA_VENDOR_DATA_DIR:
#   Halftones/COPA.DEFAULT.600x600.hft
#   Profiles/sRGB.icm
#   Profiles/sGrayInv.icm
KONICA_VENDOR_DATA_DIR=/path/to/245igdi sudo -E \
  scripts/build-and-install-printer-app.sh
```

## Secrets

No credentials, tokens or secrets are stored in this repository. The PAPPL
administration interface is unauthenticated by design and is kept on localhost.
The CUPS proxy does not add authentication either; it relies on the host's own
CUPS access controls.

## CUPS and the legacy chain

- Fedora's CUPS service is not replaced, stopped or reconfigured by these
  scripts.
- The legacy `cups-filters` 1.28 filter chain is not installed on the Fedora
  host. The Alpine rootfs contains `cups-filters` only as the source of
  `pdftoraster` for the optional `system` renderer mode.
- No legacy Konica PPD or proprietary filter is installed for the proxy queue.

## Update and rollback safety

- Pinned Alpine release, PAPPL tag and upstream commits; no `latest` tracking.
- `create-alpine-rootfs.sh` refuses to overwrite an existing rootfs unless
  `KONICA_FORCE=1`, and moves the old tree to a timestamped `.bak` first.
- `remove-host-integration.sh` disables and removes only files created by this
  project. The old Debian/Podman service and any CUPS queue are untouched.
