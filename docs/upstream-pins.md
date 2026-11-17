# Upstream pins and dependency manifest

## Why this document exists

This project consumes upstream code rather than maintaining a fork. Exact
revisions are recorded so a rootfs built today is byte-comparable to one built
next month, and so a failed update can be traced to a specific change.

## Pinned revisions

| Input | Version / revision | Source |
|---|---|---|
| Alpine minirootfs | 3.24.2, x86_64 | https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/x86_64/alpine-minirootfs-3.24.2-x86_64.tar.gz |
| Alpine minirootfs SHA256 | `c5ca053cfe1d85c5b96dff8b9bc57045f7f184a30ffb6b65776409ca90388677` | published `.sha256` file |
| PAPPL | v1.3.1, commit `8eb465be78469c1344e7305bf02d305ee7907e36` | https://github.com/michaelrsweet/pappl |
| Printer application | commit `287ad50c9dd7b9b42f3e37ea6ed274f2b7e72ada` ("Fail startup if IPP listeners cannot be added") | https://github.com/vinod2807/konica206-native-alpine |
| Native renderer | commit `e1d522ed8c655541469b6aa49c5ecdec76b7b9d6` ("Document A4 reported as CUSTOM (595x841pt) and encoder fix") | https://github.com/vinod2807/konica-native-musl |

These values live in [`config/pins.env`](../config/pins.env) and are read by the
build scripts. CI validates that the file is complete and uses the renderer pin
directly.

## Dependency manifest (Alpine runtime)

Installed by `scripts/install-alpine-dependencies.sh`:

| Package | Why |
|---|---|
| `cups-libs` | libcups / libcupsimage, needed by the PAPPL app and by the renderer's reader cross-check |
| `libusb` | USB transport to the printer |
| `ghostscript` | `builtin` PDF renderer (`gs -sDEVICE=pgmraw`) |
| `cups-filters` | supplies `pdftoraster` for the `system` PDF renderer mode |
| `python3` | renderer test suite |
| `ca-certificates`, `tzdata` | baseline userspace |

PAPPL itself has **no Alpine package**, so it is built from the pinned tag and
installed under `/usr/local` (`libpappl.so.1`). The dynamic linker is pointed at
`/usr/local/lib` explicitly.

## Temporary build dependencies

Installed as an `apk --virtual .konica-build` set by
`scripts/build-and-install-printer-app.sh`, then removed:

`build-base`, `pkgconf`, `cups-dev`, `libusb-dev`, `libpng-dev`,
`libjpeg-turbo-dev`, `zlib-dev`, `openssl-dev`, `avahi-dev`, `python3`.

Renderer build: `make CC=cc` (pure C11, `-lm` only).
Application build: `make` (pappl, libusb-1.0, libcupsimage, libcups).

## Runtime files installed

| Path | Origin |
|---|---|
| `/usr/local/bin/konica206-native`, `konica-send`, `konica-render` | `konica206-native-alpine` |
| `/usr/local/lib/konica/konica-native` | `konica-native-musl` |
| `/usr/local/lib/libpappl.so.1` | PAPPL v1.3.1 |
| `/usr/local/lib/konica/KonicaMinolta/245igdi/Halftones/COPA.DEFAULT.600x600.hft` | **Konica proprietary — manual install** |
| `/usr/local/lib/konica/KonicaMinolta/245igdi/Profiles/sRGB.icm` | **Konica proprietary — manual install** |
| `/usr/local/lib/konica/KonicaMinolta/245igdi/Profiles/sGrayInv.icm` | **Konica proprietary — manual install** |
| `/usr/local/lib/konica/KonicaMinolta/245igdi/Profiles/*` (others) | optional vendor data, not required by the renderer |
| `/usr/local/share/konica/KonicaMinolta-206-native.ppd` | upstream PPD, optional for the app |

The renderer needs the halftone screen and the two ICC profiles at runtime; it
generates its colour-management table from the profiles at start-up and fails
closed (no output, non-zero exit) when they are missing.

## Proprietary data and redistribution decision

The halftone screen and ICC profiles are Konica Minolta's property. The upstream
repository documents that redistributing them requires the vendor's permission.
**Decision for this project: do not redistribute them.** No binary, archive,
rootfs image or container image published from this repository includes them.
Users supply the directory themselves from a driver they already own, via
`KONICA_VENDOR_DATA_DIR`, and the build script verifies the three mandatory
files before copying them.

## What was inspected during pinning

- `konica206-native-alpine`: README, Makefile, `INSTALL-konica206-native.md`,
  `docs/alpine-install.md`, `docs/native-filter-musl.md`, OpenRC init script,
  systemd service, environment config and udev rule.
- `konica-native-musl`: README, Makefile, runtime-data documentation and the
  vendor-free test targets.
- Application CLI: `konica206-native server -o server-port=<port>` is the
  foreground server subcommand; `-o listen=localhost|any`, `-o log-level=` and
  `-o log-file=` are supported. The pinned revision fails startup when
  listeners cannot be added, which is why the service has a bounded restart
  policy rather than an infinite retry loop.

## Update policy

1. Change a pin in `config/pins.env` and this document together.
2. Rebuild in a scratch rootfs; never mutate the known-good one in place.
3. Run `make check` for both upstream projects (CI covers the renderer).
4. Re-run the smoke subset of the physical acceptance matrix before switching
   the service over.
5. Keep the previous rootfs snapshot until the new one has printed successfully.

Do not track `latest` tags or rolling distro branches.
