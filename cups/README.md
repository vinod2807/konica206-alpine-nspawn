# Optional Fedora CUPS driverless IPP proxy

Fedora's CUPS is **not** replaced by this project. If desktop applications need
a conventional CUPS queue, add a driverless IPP proxy that relays jobs to the
PAPPL endpoint inside the container. The proxy never touches USB, so it adds no
contention with the PAPPL app.

## Queue with real page-size names (recommended)

`-m everywhere` makes CUPS 3 name every size `<size>.Borderless` (because the
driver reports zero margins). For plain, real media names with A4 and simplex
defaults, use the driverless-generated PPD shipped by the pinned upstream app.
It lists **A3, A4, A5, A6, Executive, Legal, Letter, Statement** with full-page
image areas, no `.Borderless` variants, `*DefaultPageSize: A4` and
`*DefaultDuplex: None`.

The example uses port `8002`, the recommended port when an existing printer
application already owns 8001 (see [../README.md](../README.md)).

```sh
PPD=/var/lib/konica206-nspawn/konica206-native.ppd
sudo install -D -m 644 cups/konica206-native.ppd "$PPD"
sudo lpadmin -p konica206-nspawn -E \
  -v ipp://127.0.0.1:8002/ipp/print/konica206 \
  -P "$PPD" -o printer-error-policy=retry-job
sudo lpadmin -p konica206-nspawn -o PageSize=A4 -o Duplex=None
sudo cupsaccept konica206-nspawn && sudo cupsenable konica206-nspawn
lpoptions -p konica206-nspawn -l
```

Expected options:

```text
PageSize/Media Size: A3 *A4 A5 A6 Executive Legal Letter Statement
Duplex/2-Sided Printing: *None DuplexNoTumble DuplexTumble
```

Notes:

- `cups/konica206-native.ppd` is generated from the app's own IPP attributes by
  `driverless` in the upstream project. It contains no proprietary Konica data
  and adds no local filter chain: jobs are relayed as PDF to PAPPL.
- `ISOB4`/`ISOB5` are deliberately absent: those names are not standard Windows
  paper IDs and are known to crash Wine's `gdi32`.
- `-E` is required. Without it `lpadmin` creates a disabled queue that is not
  accepting jobs; a later `cupsenable` alone does not fix
  `printer-is-accepting-jobs=false`.
- Run `lpadmin` **while the queue is idle**. Changing a queue's PPD on a busy
  queue can restart an active job from page 1.
- Print to the **CUPS queue name**: `lp -d konica206-nspawn file.pdf`. The name
  `konica206` exists only inside PAPPL and will fail from the host.

## Minimal `-m everywhere` alternative

If you do not care about the `.Borderless` names:

```sh
lpadmin -p konica206-ipp -E \
  -v ipp://127.0.0.1:8001/ipp/print/konica206 \
  -m everywhere
lpadmin -p konica206-ipp -o printer-error-policy=retry-job
lpadmin -p konica206-ipp -o media-default=iso_a4_210x297mm -o sides-default=one-sided
```

## Validate without paper

```sh
ipptool -tv ipp://localhost:631/printers/konica206-nspawn \
  /var/lib/konica206-nspawn/get-printer-attributes.test
lpstat -p konica206-nspawn -l
```

Driverless discovery/capabilities can also be checked with
`driverless ipp://127.0.0.1:8002/ipp/print/konica206`.

## Remove

```sh
lpadmin -x konica206-nspawn
lpadmin -x konica206-ipp 2>/dev/null
```

This removes only the queues created above. It never touches the pre-existing
`konica206`, `konica206uri`, `KONICA_MINOLTA_206` / Debian-Podman queues or
`/etc/cups` configuration.

## Alternative: direct IPP

Applications that can print to IPP directly may target
`ipp://127.0.0.1:8002/ipp/print/konica206` (from the host) or the equivalent
URI with the host's address if you deliberately change `listen=any`. Keep the
default `listen=localhost` unless you have reviewed
[../docs/security.md](../docs/security.md).
