# Fedora bootc integration

## Chosen model: A — host-managed mutable rootfs

For this proof of concept the Alpine rootfs lives at
`/var/lib/machines/alpine-konica`, **outside** the immutable bootc image. Only
host service/configuration files are baked into a derived bootc image.

Why:

- The rootfs can be rebuilt, snapshotted and rolled back without rebuilding or
  rebooting into a new bootc image.
- Proprietary Konica runtime data never enters an image: it is installed
  locally on the host with `KONICA_VENDOR_DATA_DIR`.
- bootc rollback remains simple — the application data is not part of the
  image transaction.

The alternative, model B (image-baked rootfs), is described below but is not
used here; do not mix the two without a migration plan.

## Host files that belong in the bootc image

These are the files installed by `scripts/install-host-integration.sh` that are
safe to bake into an derived image (they contain no host-specific secrets or
proprietary data):

- `/etc/systemd/nspawn/alpine-konica.nspawn`
- `/etc/systemd/system/systemd-nspawn@alpine-konica.service.d/override.conf`
- `/etc/udev/rules.d/70-konica206.rules`
- `/etc/systemd/system/konica206-healthcheck.service`
- `/etc/systemd/system/konica206-healthcheck.timer`
- `/usr/local/lib/konica206/health-check.sh`
- `/usr/local/lib/konica206/get-printer-attributes.test`

Example derived-image `Containerfile` (from the repository root):

```dockerfile
FROM <your-existing-fedora-bootc-image>

COPY config/nspawn/alpine-konica.nspawn /etc/systemd/nspawn/alpine-konica.nspawn
COPY config/systemd/systemd-nspawn@alpine-konica.service.d/override.conf \
     /etc/systemd/system/systemd-nspawn@alpine-konica.service.d/override.conf
COPY udev/70-konica206.rules /etc/udev/rules.d/70-konica206.rules
COPY systemd/konica206-healthcheck.service /etc/systemd/system/konica206-healthcheck.service
COPY systemd/konica206-healthcheck.timer /etc/systemd/system/konica206-healthcheck.timer
COPY scripts/health-check.sh /usr/local/lib/konica206/health-check.sh
COPY config/ipp/get-printer-attributes.test /usr/local/lib/konica206/get-printer-attributes.test
RUN chmod 0755 /usr/local/lib/konica206/health-check.sh

RUN systemctl enable systemd-nspawn@alpine-konica.service konica206-healthcheck.timer
```

After booting the new image, the rootfs still has to be created once on the
host with the three rootfs scripts. Because a bootc host keeps `/var` mutable,
the rootfs survives image updates; keep a `.bak` snapshot of it before any
rebuild.

## Rollback

One-command disable of the new path:

```sh
sudo scripts/remove-host-integration.sh
```

This disables the nspawn service and health timer, removes only the host files
listed above, and leaves `/var/lib/machines/alpine-konica` intact. Add
`KONICA_REMOVE_ROOTFS=1` to move the rootfs aside to a timestamped `.disabled`
directory.

Then restore the previously working setup:

```sh
# Example — use the exact unit name you stopped before testing.
sudo systemctl enable --now <your-debian-podman-printer-service>
sudo systemctl status cups
lpstat -p   # confirm the legacy KONICA_MINOLTA_206 queue is still present
```

If you created the optional CUPS proxy queue, remove only that queue:

```sh
lpadmin -x konica206-ipp
```

Do not disable or delete the legacy service/queue until the physical acceptance
matrix in [testing-and-acceptance.md](testing-and-acceptance.md) has passed
repeatedly.

## Model B — image-baked rootfs (not implemented)

If image size and update semantics are acceptable later, the rootfs can be
built during the container-image build and shipped inside the bootc image.
This requires:

- a multi-stage build that cross-builds or emulates Alpine/musl,
- deterministic handling of the proprietary runtime-data step (which cannot be
  baked here without redistribution permission),
- verification that a bootc update replaces the rootfs atomically and that
  rollback restores the previous one,
- a migration procedure from the mutable `/var/lib/machines` tree.

Revisit this only after model A has passed physical testing and the image-size
trade-off has been measured.
