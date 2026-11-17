# Testing and acceptance

CI validates scripts, configuration, unit syntax and the vendor-free renderer
build. It cannot validate USB printing. Everything below is a **manual gate on
the target Fedora bootc machine with the bizhub 206 attached**.

## Preflight (no paper)

```sh
# Service and container
systemctl status systemd-nspawn@alpine-konica.service
machinectl status alpine-konica

# IPP endpoint
ipptool -tv ipp://127.0.0.1:8001/ipp/print/konica206 \
  /var/lib/konica206-nspawn/get-printer-attributes.test

# Vendor-free upstream tests (run inside the rootfs before build tools are removed)
# make check          in konica206-native-alpine
# make check          in konica-native-musl

# Runtime data present?
ls -l /var/lib/machines/alpine-konica/usr/local/lib/konica/KonicaMinolta/245igdi/Halftones/
ls -l /var/lib/machines/alpine-konica/usr/local/lib/konica/KonicaMinolta/245igdi/Profiles/

# Resource baseline
du -sh /var/lib/machines/alpine-konica
systemctl show systemd-nspawn@alpine-konica.service -p MemoryCurrent -p CPUUsageNSec
ps -eo pid,rss,vsz,comm,args | grep -E 'konica206-native|systemd-nspawn'
```

Expected IPP attributes: `printer-make-and-model = KONICA MINOLTA 206`,
A4 default, one-sided default, sides supports long/short edge, 600 dpi default
(300 also supported), monochrome, and formats including PDF, PWG raster, URF,
JPEG and PNG.

## Physical acceptance matrix

Run one test at a time with the printer connected by USB and record the result.
Do not proceed to retirement of the old path until every required row passes
**repeatedly**.

| # | Test | Required result | Pass? | Notes / log excerpt |
|---|---|---|---|---|
| 1 | Application starts with no printer attached | Service stays healthy; clear device-wait state, no restart loop | ☐ | |
| 2 | USB printer detected | Correct `132b:232b` device and serial identified | ☐ | |
| 3 | A4 text, simplex | Correct output | ☐ | |
| 4 | A4 PDF, simplex | Correct output | ☐ | |
| 5 | A4 duplex, long edge | Correct orientation | ☐ | |
| 6 | A4 duplex, short edge | Correct orientation | ☐ | |
| 7 | Multiple copies (2–3) | Correct copy count, collated | ☐ | |
| 8 | Photo / grayscale image | Acceptable halftone and image quality | ☐ | |
| 9 | Large / multi-page PDF | No crash, truncation or blank pages | ☐ | |
| 10 | USB unplug / replug | Recovers without host reboot | ☐ | |
| 11 | PAPPL / container restart | Printer available again | ☐ | |
| 12 | Fedora reboot | Service returns automatically | ☐ | |
| 13 | Fedora CUPS proxy queue | Jobs submit and complete | ☐ | |
| 14 | Concurrent / repeated jobs | No stuck queue or corruption | ☐ | |
| 15 | Renderer comparison: `builtin` vs `system` | Both complete; chosen default documented | ☐ | |
| 16 | Paper sizes / trays claimed as supported | Behave as documented; unsupported ones listed | ☐ | |

Suggested submission command (no banner pages — they wedge this printer):

```sh
ipptool -tv -f test.pdf -d filetype=application/pdf \
  -d sides=two-sided-long-edge -d media=iso_a4_210x297mm -d copies=2 \
  ipp://127.0.0.1:8001/ipp/print/konica206 print-job.test
```

After each job check the log for `Render failed`, `USB transfer failed` or
`Unable to open device`:

```sh
journalctl -u systemd-nspawn@alpine-konica.service -n 100 --no-pager
```

## Resource measurements

Do not use estimates. Measure on the target with the same documents and
settings for every comparison:

```sh
du -sh /var/lib/machines/alpine-konica
machinectl status alpine-konica
systemd-cgtop
systemctl show systemd-nspawn@alpine-konica.service -p MemoryCurrent -p CPUUsageNSec
ps -eo pid,rss,vsz,comm,args | grep -E 'konica206-native|systemd-nspawn'
/usr/bin/time -v ipptool ... print-job.test
```

Record idle PSS/RSS, peak memory during text / PDF / photo jobs, CPU time and
wall-clock preparation time, and the host baseline with the service stopped.

## Acceptance gate

Do **not** disable or remove the known-working Debian/Podman printer service
until rows 1–14 pass repeatedly on the target machine. Keep the previous rootfs
`.bak` snapshot and the old CUPS proxy queue available until then.
