#!/bin/sh
# Verify that the PAPPL IPP endpoint is answering on localhost.
# Used by konica206-healthcheck.service / .timer; also useful by hand.
#
#   /var/lib/konica206-nspawn/health-check.sh
#   IPP_PORT=8001 sh scripts/health-check.sh        # from a source checkout
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
# Precedence: environment, then the port file written at install time, then 8001.
PORT=${IPP_PORT:-}
if [ -z "$PORT" ] && [ -r "$HERE/port" ]; then
    PORT=$(cat "$HERE/port")
fi
PORT=${PORT:-8001}
URL="ipp://127.0.0.1:$PORT/ipp/print/konica206"
# Installed layout: test file sits next to this script (/var/lib/konica206-nspawn).
# Source checkout: it is under config/ipp/ instead.
if [ -r "$HERE/get-printer-attributes.test" ]; then
    DEFAULT_TEST="$HERE/get-printer-attributes.test"
else
    DEFAULT_TEST="$HERE/../config/ipp/get-printer-attributes.test"
fi
TEST_FILE=${KONICA_IPP_TEST:-$DEFAULT_TEST}
UNIT="systemd-nspawn@${MACHINE_NAME:-alpine-konica}.service"

if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl is-active --quiet "$UNIT" 2>/dev/null; then
        echo "NOTE: $UNIT is not active" >&2
    fi
fi

if command -v ipptool >/dev/null 2>&1 && [ -r "$TEST_FILE" ]; then
    OUT=$(ipptool -t -q "$URL" "$TEST_FILE" 2>&1) || {
        echo "UNHEALTHY: ipptool could not reach $URL" >&2
        echo "$OUT" >&2
        exit 1
    }
    case "$OUT" in
        *printer-name*)
            echo "HEALTHY: $URL answered GetPrinterAttributes"
            exit 0
            ;;
        *)
            echo "UNHEALTHY: unexpected response from $URL" >&2
            echo "$OUT" >&2
            exit 1
            ;;
    esac
fi

# Shallow fallback: any HTTP response means the listener is up. Use ipptool
# for a real check (the cups-ipptool package on Fedora).
if command -v curl >/dev/null 2>&1; then
    CODE=$(curl -sS -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/ipp/print/konica206" 2>/dev/null || true)
    case "$CODE" in
        000|'')
            echo "UNHEALTHY: no HTTP response from 127.0.0.1:$PORT" >&2
            exit 1
            ;;
        *)
            echo "HEALTHY (shallow HTTP probe only; install ipptool for a full check)"
            exit 0
            ;;
    esac
fi

echo "UNHEALTHY: neither ipptool nor curl is available" >&2
exit 1
