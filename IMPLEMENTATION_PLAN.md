# Konica Minolta bizhub 206 on Fedora bootc
## Alpine + systemd-nspawn implementation plan

**Proposed repository:** `konica206-alpine-nspawn`  
**Purpose:** Document and implement a small, isolated Alpine PAPPL printer application for the Konica Minolta bizhub 206, managed by Fedora's systemd on a Fedora bootc host.

> This repository is an integration/deployment project. It should consume the existing upstream projects rather than fork or duplicate their renderer/application code:
>
> - `https://github.com/vinod2807/konica206-native-alpine`
> - `https://github.com/vinod2807/konica-native-musl`

## 1. Goals

1. Run the native Konica PAPPL application from a minimal Alpine root filesystem.
2. Use `systemd-nspawn` for the Alpine environment; do not require Podman or Docker.
3. Start the environment and printer application automatically at Fedora boot.
4. Give the application access only to the required USB printer device.
5. Expose PAPPL's IPP endpoint locally, initially on port `8001`.
6. Optionally create a Fedora CUPS driverless IPP proxy queue.
7. Keep the existing Debian/Podman printer setup available as a rollback until the new path passes physical-printer testing.
8. Make the installation reproducible and suitable for a Fedora bootc image.

## 2. Non-goals

- Do not replace Fedora's CUPS service.
- Do not install cups-filters 1.28.x on Fedora.
- Do not run a second full CUPS daemon inside Alpine.
- Do not include or redistribute Konica proprietary runtime data unless its redistribution licence has been reviewed.
- Do not expose PAPPL's administration interface to an untrusted network.
- Do not remove the known-working Debian/Podman setup before acceptance tests pass.

## 3. Proposed architecture

```text
Fedora bootc host
|
+-- systemd
|   |
|   +-- systemd-nspawn@alpine-konica.service
|       |
|       +-- Alpine root filesystem (/var/lib/machines/alpine-konica)
|           |
|           +-- PAPPL application: konica206-native
|               |
|               +-- konica-native C11 renderer
|               +-- libusb access to bizhub 206
|               +-- IPP listener (initially localhost:8001)
|
+-- Fedora CUPS (optional)
    |
    +-- driverless IPP proxy queue
        ipp://127.0.0.1:8001/ipp/print/konica206
```

Fedora systemd should own the container lifecycle. The Alpine image should remain a minimal userspace, not a second general-purpose server installation.

### Important service-management decision

The upstream Alpine project documents an OpenRC service. Do not assume that OpenRC will be PID 1 or that `rc-update` will work in this deployment.

Preferred approach:
- Start the nspawn machine with Fedora's `systemd-nspawn@.service`.
- Run the PAPPL executable as the container's main process using a dedicated, reviewed nspawn service override or a small host-side launcher.
- Ensure systemd can stop and restart the PAPPL process cleanly.
- Avoid starting a full Alpine init system unless testing proves it is necessary.

The exact execution mechanism must be verified against the installed systemd version and the upstream PAPPL application's command-line behaviour before writing the final service unit.

## 4. Repository structure

```text
konica206-alpine-nspawn/
├── README.md
├── IMPLEMENTATION_PLAN.md
├── docs/
│   ├── architecture.md
│   ├── security.md
│   ├── testing-and-acceptance.md
│   ├── troubleshooting.md
│   └── bootc-integration.md
├── config/
│   ├── nspawn/
│   │   └── alpine-konica.nspawn
│   └── systemd/
│       └── systemd-nspawn@alpine-konica.service.d/
│           └── override.conf
├── scripts/
│   ├── create-alpine-rootfs.sh
│   ├── install-alpine-dependencies.sh
│   ├── build-and-install-printer-app.sh
│   ├── install-host-integration.sh
│   ├── remove-host-integration.sh
│   └── health-check.sh
├── systemd/
│   ├── konica206-container.service
│   └── konica206-healthcheck.service
├── udev/
│   └── 70-konica206.rules
├── cups/
│   └── README.md
└── .github/
    └── workflows/
        └── validate.yml
```

Only add files that are needed by the chosen service model. In particular, do not ship both competing service designs as if both were active.

## 5. Implementation phases

### Phase 0 — Inspect and pin upstream inputs

- Inspect the current `konica206-native-alpine` README, Makefile, source, install instructions and service definition.
- Inspect `konica-native-musl` build options, runtime data requirements and test suite.
- Record exact upstream commit IDs or release tags used by this project.
- Confirm the application can be built for Alpine x86_64 with the intended PAPPL, CUPS raster, libusb and PDF-rendering dependencies.
- Identify which runtime files are required: renderer binary, PAPPL application, halftone data, ICC profiles and configuration.
- Review redistribution rights for proprietary Konica data. Prefer a documented manual installation step if redistribution is not permitted.

**Deliverable:** `docs/upstream-pins.md` and a dependency manifest.

### Phase 1 — Build a minimal Alpine root filesystem

- Use a pinned Alpine minirootfs release and architecture.
- Install only the packages required to run the application and render jobs.
- Do not install a full desktop, development toolchain or full CUPS daemon in the runtime rootfs.
- Keep compiler/build dependencies in a separate build stage or temporary build environment.
- Decide whether PDF rendering uses the Alpine system `pdftoraster` path or the project's builtin renderer.
- Start with the upstream default renderer mode; test the builtin mode separately before making it the default.
- Record compressed rootfs size and installed package footprint.

**Deliverable:** reproducible rootfs creation script and package list.

### Phase 2 — Build and install the printer application

- Build `konica-native` for Alpine/musl using the upstream project.
- Build `konica206-native` against the pinned PAPPL, CUPS raster and libusb development libraries.
- Install binaries and runtime assets into stable paths, for example:
  - `/usr/local/bin/konica206-native`
  - `/usr/local/lib/konica/konica-native`
  - `/usr/local/share/konica206/` for permitted runtime data
- Confirm dynamic library dependencies with Alpine tools such as `ldd`.
- Run upstream unit and native-renderer tests.
- Do not claim full printer support based solely on compilation or mock tests.

**Deliverable:** build script, install manifest and test report.

### Phase 3 — Configure systemd-nspawn

- Place the root filesystem at `/var/lib/machines/alpine-konica`.
- Create a machine configuration under `/etc/systemd/nspawn/alpine-konica.nspawn`.
- Configure a stable machine name and an explicit network strategy.
- Prefer a host-only listener initially. If the IPP endpoint must be reachable from the LAN, document firewall rules and restrict the PAPPL administration interface.
- Pass through only the required USB device or device tree; avoid unrestricted privileged access where possible.
- Confirm USB device permissions survive unplug/replug.
- Confirm the container can resolve any required local dependencies without exposing unnecessary host services.

**Deliverable:** nspawn configuration and a documented USB/network setup.

### Phase 4 — Boot-time service integration

- Enable `systemd-nspawn@alpine-konica.service`.
- Ensure the PAPPL application is started and supervised inside the nspawn environment.
- Configure restart-on-failure with a sensible delay.
- Ensure stop/reboot shuts down PAPPL cleanly.
- Ensure the machine does not enter a restart loop if the USB printer is disconnected.
- Add a health check that confirms the IPP endpoint responds.
- Document logs and diagnostic commands.

**Deliverable:** tested boot-time service configuration.

### Phase 5 — Fedora CUPS integration (optional)

- Keep Fedora CUPS as the host print scheduler if desired.
- Add a driverless IPP Everywhere proxy queue pointing to:
  `ipp://127.0.0.1:8001/ipp/print/konica206`
- Do not install the legacy Konica PPD or proprietary filter chain on the Fedora host for this queue.
- Verify Fedora's CUPS can discover capabilities and submit jobs.
- Document direct IPP printing as an alternative to the host proxy queue.

**Deliverable:** optional queue setup/removal instructions.

### Phase 6 — Physical printer validation

Run tests with the actual bizhub 206 connected by USB. Capture logs and retain sample output where practical.

Minimum acceptance matrix:

| Test | Required result |
|---|---|
| Application starts without printer | Service remains healthy or reports a clear device-wait state |
| USB printer detected | Correct device identified |
| A4 text, simplex | Correct output |
| A4 PDF, simplex | Correct output |
| A4 duplex, long edge | Correct orientation and output |
| A4 duplex, short edge | Correct orientation and output |
| Multiple copies | Correct copy count |
| Photo / grayscale image | Acceptable halftone and image quality |
| Large/multi-page PDF | No crash, truncation or unexpected blank pages |
| USB unplug/replug | Device recovers without host reboot |
| PAPPL/container restart | Printer becomes available again |
| Fedora reboot | Printer service returns automatically |
| Host CUPS proxy queue | Jobs submit and complete successfully |
| Concurrent/repeated jobs | No stuck queue or data corruption |

Also test paper sizes and trays that the project claims to support. Record unsupported features explicitly.

**Acceptance gate:** Do not retire the existing Debian/Podman path until all required tests pass repeatedly on the target Fedora bootc machine.

### Phase 7 — Fedora bootc packaging

Choose one of two deployment models and document it clearly:

**A. Host-managed mutable rootfs**
- Create/update `/var/lib/machines/alpine-konica` using an installation/update script.
- Keep the rootfs outside the immutable bootc image.
- Install only host service/configuration files into the bootc image.
- Ensure rootfs backups and updates are explicit.

**B. Image-baked rootfs**
- Build the Alpine rootfs during the bootc image build and include it in the image.
- Confirm the image build can reproduce the rootfs and that updates replace it safely.
- Account for image size and bootc rollback behaviour.

Do not mix the two models without a clear migration strategy. For an initial proof of concept, use the host-managed rootfs; later decide whether baking it into the bootc image is worth the image-size and update trade-off.

### Phase 8 — Maintenance and rollback

- Pin Alpine release and upstream source revisions.
- Document a deliberate update process; do not blindly track `latest`.
- Run renderer tests and physical smoke tests after updates.
- Keep a known-good rootfs snapshot or archive before upgrades.
- Provide a one-command disable/rollback procedure.
- Keep the existing Debian/Podman printer service disabled but available until the new setup is accepted.
- Document how to restore the old Fedora CUPS proxy queue.

## 6. Security requirements

- Do not run PAPPL's unauthenticated administration interface on an untrusted LAN.
- Bind to localhost by default.
- Do not use `--privileged` as a shortcut.
- Pass through only the printer's required USB device access.
- Avoid sharing the host's entire `/dev`, `/proc` or `/sys` tree unless required and justified.
- Use a dedicated service identity where feasible; document device-group/udev permissions.
- Keep proprietary Konica runtime files out of public releases unless redistribution permission is established.
- Do not store credentials or secrets in the repository.

## 7. Resource measurement

Do not use estimated RAM figures as acceptance evidence. Measure on the target machine.

Record:
- Alpine rootfs disk usage (`du -sh`).
- Installed package footprint.
- Idle memory (PSS/RSS where available) for PAPPL and nspawn.
- Peak memory during text, PDF and photo jobs.
- CPU time and wall-clock print preparation time.
- Host baseline versus printer service running.

Suggested commands:

```bash
du -sh /var/lib/machines/alpine-konica
machinectl status alpine-konica
systemd-cgtop
systemctl show systemd-nspawn@alpine-konica.service \
  -p MemoryCurrent -p CPUUsageNSec
ps -eo pid,rss,vsz,comm,args | grep -E 'konica206-native|systemd-nspawn'
```

Use the same test documents and print settings for all comparisons.

## 8. CI validation

GitHub Actions should:
- Validate shell scripts with `shellcheck` when available.
- Run `sh -n` on POSIX shell scripts.
- Check systemd unit syntax where a suitable validator is available.
- Verify configuration files and required paths.
- Build/test upstream renderer and PAPPL application in a pinned Alpine environment when practical.
- Avoid pretending that CI can validate physical USB printing. Physical printer tests remain a manual acceptance gate.

Do not publish a production image or update the user's bootc host automatically until the build and physical test gates are defined and passed.

## 9. Definition of done

The project is complete when:

1. A reproducible Alpine rootfs can be created from pinned inputs.
2. PAPPL and `konica-native` build and install successfully.
3. The nspawn machine starts automatically at Fedora boot.
4. PAPPL starts reliably and exposes the documented local IPP endpoint.
5. USB disconnect/reconnect is handled.
6. The full physical acceptance matrix passes on the bizhub 206.
7. Optional Fedora CUPS proxy printing works.
8. Disk/RAM/CPU measurements are recorded on the target machine.
9. Rollback to the existing Debian/Podman setup is documented and tested.
10. Security and proprietary-data redistribution decisions are documented.

## 10. Known risks and open technical decisions

- The upstream project's Alpine OpenRC service is not automatically a valid nspawn service design.
- Exact PAPPL command-line arguments and foreground/daemon mode must be confirmed from the current source.
- USB device node ownership and hotplug handling need testing under nspawn.
- PDF rendering mode (`system` versus `builtin`) needs comparative physical testing.
- PAPPL/CUPS raster library dependencies must not be confused with a dependency on cups-filters 1.28.x. The target is to avoid the legacy filter chain, not necessarily every CUPS library.
- The Fedora CUPS proxy queue must be tested against the target Fedora release.
- The final rootfs size and memory footprint must be measured, not inferred from generic estimates.

## 11. Initial execution order

1. Inspect and pin both upstream repositories.
2. Build the Alpine rootfs and app manually.
3. Test PAPPL and USB printing interactively.
4. Add nspawn configuration.
5. Add boot-time systemd supervision.
6. Test the IPP endpoint and optional Fedora CUPS proxy.
7. Complete physical acceptance tests.
8. Measure resource usage.
9. Add bootc packaging and rollback.
10. Publish a tagged, reproducible release.
