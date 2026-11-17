# Architecture

## Components

| Layer | Owner | Notes |
|---|---|---|
| Fedora bootc host systemd | Fedora | Owns the container lifecycle (`systemd-nspawn@alpine-konica.service`). |
| systemd-nspawn | systemd | Runs the Alpine rootfs with a host network namespace and a bind of `/dev/bus/usb`. |
| Alpine rootfs (`/var/lib/machines/alpine-konica`) | this project | Minimal userspace: musl, libcups, libusb, Ghostscript, PAPPL, the app and the renderer. No cupsd, no OpenRC. |
| `konica206-native` | upstream | PAPPL application. `server -o server-port=8001 -o listen=localhost` is the container's main process. |
| `konica-native` | upstream | Pure-C11 renderer, invoked by the app as a CUPS-filter-style child with raster on stdin. |
| Fedora CUPS | Fedora | Optional driverless IPP proxy queue only; it never opens the USB device. |

## Runtime data flow

```
IPP client (host or local app)
    → 127.0.0.1:8001/ipp/print/konica206
    → PAPPL (inside nspawn)
    → PDF: 'builtin' renderer (gs -sDEVICE=pgmraw + own raster writer)
       or 'system' renderer (cups-filters pdftoraster)
    → CUPS raster
    → konica-native (halftone screen + ICC profiles → JBIG1 + PJL stream)
    → libusb, 8192-byte writes → bizhub 206 USB interface 1
```

The `builtin` PDF renderer is the upstream unit's default; the `system` path is
installed so both can be compared during physical testing. Only one process may
own USB interface 1: the legacy Debian/Podman stack and this app must not print
at the same time.

## Service model

The implementation plan allowed either a custom container unit or a drop-in for
the distribution template (with a possible host-side launcher). This project
uses **only the drop-in**:

- `systemd-nspawn@.service` is supplied by Fedora, so machine lifecycle
  (`machinectl`, clean shutdown, cgroup handling) stays idiomatic.
- `config/systemd/systemd-nspawn@alpine-konica.service.d/override.conf` clears
  the template's `ExecStart` and supplies a reviewed `systemd-nspawn` command.
  The default template boots `/sbin/init` with `--network-veth` and private
  users; all three are removed.
- The command names `/usr/local/bin/konica206-native server ...` explicitly as
  the program to run inside the container. `systemd-nspawn` without `--boot`
  runs that program as the container's main process; Alpine's OpenRC service is
  intentionally **not** used.
- `config/nspawn/alpine-konica.nspawn` holds machine-level settings (hostname,
  network namespace, USB binds). It has no `[Exec]` section, so there is a
  single place that decides how the app is started.

`Type=simple` is set because the PAPPL process does not send readiness
notifications. `Restart=on-failure` with `RestartSec=10s` and
`StartLimitIntervalSec=300` / `StartLimitBurst=5` gives bounded recovery. A
printer that is simply unplugged does **not** stop the app: PAPPL lists no device
and keeps serving the IPP endpoint, so no restart loop occurs.

## Network

`Private=no` and `VirtualEthernet=no` mean the container shares the host network
namespace. Consequently the container's `127.0.0.1` is the host's
`127.0.0.1`, which is what makes the CUPS proxy URI
`ipp://127.0.0.1:8001/ipp/print/konica206` work without port forwarding.

`-o listen=localhost` is passed explicitly (PAPPL's own default is also
localhost in the pinned revision). Both the IPP endpoint and PAPPL's web
interface are therefore reachable only from the host. To expose IPP to the LAN,
you would have to change this deliberately and apply the firewall and
web-interface restrictions described in [security.md](security.md).

## USB

- The host udev rule (`udev/70-konica206.rules`) matches `132b:232b`, sets
  `GROUP=lp`, `MODE=0660` and `TAG+="uaccess"`, and is applied on unplug/replug
  by udev automatically.
- The nspawn config binds `/dev/bus/usb` (the USB device tree, not all of
  `/dev`) and `/sys/bus/usb/devices` read-only for libusb enumeration.
- The PAPPL app runs as root inside the container, so it can open the node
  regardless of its mode. No user namespace is used, so no capability mapping
  is required.
- If libusb cannot enumerate the printer on the target, this is the first thing
  to verify; see [troubleshooting.md](troubleshooting.md#usb-device-not-found).

## Health check

`konica206-healthcheck.timer` runs `konica206-healthcheck.service` two minutes
after boot and every five minutes thereafter. The service runs
`/usr/local/lib/konica206/health-check.sh`, which issues a `GetPrinterAttributes`
request against the local IPP endpoint with `ipptool`. A shallow `curl` probe is
used as a fallback when `ipptool` is unavailable, but `cups-ipptool` is
recommended for a meaningful check.

## Deployment model

Host-managed mutable rootfs (model A) is used for the proof of concept. The
Alpine tree is outside the immutable bootc image and can be snapshotted,
replaced and rolled back independently; only host service/configuration files
are baked into a derived bootc image. See [bootc-integration.md](bootc-integration.md).
