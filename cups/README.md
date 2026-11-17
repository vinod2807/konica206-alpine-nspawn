# Optional Fedora CUPS driverless IPP proxy

Fedora's CUPS is **not** replaced by this project. If desktop applications need
a conventional CUPS queue, add a driverless IPP Everywhere proxy that relays
jobs to the PAPPL endpoint inside the container. The proxy never touches USB,
so it adds no contention with the PAPPL app.

## Add

Run this only after the nspawn service and the IPP endpoint are healthy:

```sh
lpadmin -p konica206-ipp -E \
  -v ipp://127.0.0.1:8001/ipp/print/konica206 \
  -m everywhere
lpadmin -p konica206-ipp -o printer-error-policy=retry-job
lpstat -p konica206-ipp
```

Important:

- `-E` is required. Without it `lpadmin` creates a disabled queue that is not
  accepting jobs; a later `cupsenable` does not fix
  `printer-is-accepting-jobs=false` (you would also need `cupsaccept`).
- Run `lpadmin` **while the queue is idle**. Regenerating an `everywhere` PPD on
  a busy queue restarts an active job from page 1.
- Print to the **CUPS queue name**: `lp -d konica206-ipp file.pdf`. The name
  `konica206` exists only inside PAPPL and will fail from the host.
- Do not install the legacy Konica PPD or the proprietary filter chain for
  this queue. CUPS generates its own small `ippeve` PPD.
- The generated PPD names every size with a `.Borderless` suffix because the
  driver reports zero margins. That is cosmetic; the IPP values are correct.

## Validate without paper

```sh
ipptool -tv ipp://localhost:631/printers/konica206-ipp \
  /var/lib/konica206-nspawn/get-printer-attributes.test
```

Driverless discovery/capabilities can also be checked with
`driverless ipp://127.0.0.1:8001/ipp/print/konica206`.

## Remove

```sh
lpadmin -x konica206-ipp
```

This removes only the queue created above. It never touches the pre-existing
`KONICA_MINOLTA_206` / Debian-Podman queue or `/etc/cups` configuration.

## Alternative: direct IPP

Applications that can print to IPP directly may target
`ipp://127.0.0.1:8001/ipp/print/konica206` (from the host) or the equivalent
URI with the host's address if you deliberately change `listen=any`. Keep the
default `listen=localhost` unless you have reviewed `docs/security.md`.
