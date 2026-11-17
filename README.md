# konica206-alpine-nspawn

An **integration/deployment project** that runs the existing
[konica206-native-alpine](https://github.com/vinod2807/konica206-native-alpine)
PAPPL printer application for the **Konica Minolta bizhub 206** inside a minimal
Alpine root filesystem, supervised by **Fedora's systemd-nspawn** on a Fedora
bootc host.

This repository contains rootfs build scripts, host integration files,
documentation and CI. It **does not fork or duplicate** the upstream renderer
or application code, and it **does not contain Konica proprietary runtime data**.

> **Status: proof of concept.** Static validation and vendor-free upstream
> builds run in CI. The physical printer acceptance matrix in
> [docs/testing-and-acceptance.md](docs/testing-and-acceptance.md) is a manual
> gate that must pass on the target machine before the old Debian/Podman path
> is retired. Do not treat a green CI run as proof that printing works.

## Architecture

```
Fedora bootc host (systemd)
└── systemd-nspawn@alpine-konica.service        ← distro template + our drop-in
    └── /var/lib/machines/alpine-konica         ← pinned Alpine minirootfs
        └── konica206-native server ...          ← container's main process (PID 1)
            ├── konica-native (renderer)
            ├── libusb → /dev/bus/usb (printer 132b:232b)
            └── IPP listener 127.0.0.1:8001  (localhost only)

Fedora CUPS (optional, host-owned)
└── driverless IPP proxy → ipp://127.0.0.1:8001/ipp/print/konica206
```

Full details: [docs/architecture.md](docs/architecture.md).

## Why there is no `konica206-container.service`

The plan proposed both a custom container unit and a drop-in for the
distribution's `systemd-nspawn@.service`. We deliberately implemented **one**
model: the stock template plus
[`config/systemd/systemd-nspawn@alpine-konica.service.d/override.conf`](config/systemd/systemd-nspawn@alpine-konica.service.d/override.conf).
The override replaces the template defaults (private users, private network,
`/sbin/init`) and passes the PAPPL executable directly to `systemd-nspawn`, so
no Alpine init is needed. Shipping a second, competing unit would make the
active design ambiguous; see [docs/architecture.md](docs/architecture.md#service-model).

## Pinned inputs

Single source of truth: [`config/pins.env`](config/pins.env); rationale and
dependency manifest: [docs/upstream-pins.md](docs/upstream-pins.md).

| Input | Pin |
|---|---|
| Alpine minirootfs | 3.24.2 x86_64 (`c5ca053c…b6b65776409ca90388677`) |
| PAPPL | v1.3.1 (`8eb465be…7907e36`) |
| Application | `konica206-native-alpine` `287ad50c…e72ada` |
| Renderer | `konica-native-musl` `e1d522ed…b7b9d6` |

## Deploy on the target Fedora bootc host

All commands run on the **target machine**, never on a developer workstation.
The host-managed mutable-rootfs model ([docs/bootc-integration.md](docs/bootc-integration.md))
is used for this proof of concept; the Alpine rootfs lives outside the
immutable bootc image.

```sh
# 1. Create and pin the Alpine root filesystem (keeps a .bak on replacement).
sudo scripts/create-alpine-rootfs.sh

# 2. Install runtime packages only.
sudo scripts/install-alpine-dependencies.sh

# 3. Build PAPPL + renderer + app from pinned sources, then drop build tools.
#    Proprietary data is NOT downloaded; see docs/security.md for the manual step.
sudo scripts/build-and-install-printer-app.sh

# 4. Install host config/udev/health check and enable the service (no start yet).
sudo scripts/install-host-integration.sh

# 5. Review docs/testing-and-acceptance.md, perform physical tests, then start:
sudo systemctl start systemd-nspawn@alpine-konica.service
/usr/local/lib/konica206/health-check.sh
```

Rollback at any time:

```sh
sudo scripts/remove-host-integration.sh
# restore the previously stopped Debian/Podman service; see docs/troubleshooting.md
```

### Proprietary runtime data

`konica-native` needs a 600 dpi halftone screen and two ICC profiles before it
will emit a single byte. Those files are Konica Minolta's and are **not**
redistributed here. Provide them yourself from a legally obtained driver:

```sh
KONICA_VENDOR_DATA_DIR=/path/to/245igdi sudo -E \
  scripts/build-and-install-printer-app.sh
```

The directory must contain `Halftones/COPA.DEFAULT.600x600.hft`,
`Profiles/sRGB.icm` and `Profiles/sGrayInv.icm`. See
[docs/security.md](docs/security.md#proprietary-konica-runtime-data).

## Repository layout

```text
config/
  pins.env                                   pinned versions and device facts
  ipp/get-printer-attributes.test            ipptool health probe
  nspawn/alpine-konica.nspawn                machine config (network, USB binds)
  systemd/systemd-nspawn@alpine-konica.service.d/override.conf   service drop-in
cups/README.md                               optional driverless proxy queue
docs/                                        architecture, security, testing,
                                             troubleshooting, bootc, upstream pins
scripts/                                     rootfs, build, host install/remove, health
systemd/                                     health-check oneshot + timer
udev/70-konica206.rules                      USB permissions (host side)
.github/workflows/validate.yml               shell, config, unit and renderer checks
```

## Safety properties

- Binds IPP and the unauthenticated PAPPL web interface to **localhost only**.
- No `--privileged`; only `/dev/bus/usb` is bound into the container.
- Shares the host network namespace on purpose so the CUPS proxy can reach
  `127.0.0.1:8001`; no veth, no LAN exposure.
- Does not touch Fedora's CUPS, `/etc/cups`, the Debian/Podman service, or the
  legacy queue.
- Bounded restart policy; a disconnected printer does not create a restart loop
  because PAPPL starts normally and waits for the device.

## Documentation

- [Architecture and service model](docs/architecture.md)
- [Upstream pins and dependency manifest](docs/upstream-pins.md)
- [Security decisions](docs/security.md)
- [Testing and acceptance gates](docs/testing-and-acceptance.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Fedora bootc integration and rollback](docs/bootc-integration.md)
- [Original implementation plan](IMPLEMENTATION_PLAN.md)
