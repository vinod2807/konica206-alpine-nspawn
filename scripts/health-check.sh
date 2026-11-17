#!/bin/sh
# Verify that the PAPPL IPP endpoint is answering on localhost.
# Used by konica206-healthcheck.service / .timer; also useful by hand.
# Retries briefly, because the app can take a few seconds to bind its listener.
#
#   /var/lib/konica206-nspawn/health-check.sh
#   IPP_PORT=8002 sh scripts/health-check.sh     # from a source checkout
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

probe() {
    if command -v ipptool >/dev/null 2>&1 && [ -r "$TEST_FILE" ]; then
        OUT=$(ipptool -t -q "$URL" "$TEST_FILE" 2>&1) || return 1
        case "$OUT" in
            *printer-name*) return 0 ;;
            *) return 1 ;;
        esac
    fi

    # Shallow fallback: any HTTP response means the listener is up. Use ipptool
    # for a real check (the cups-ipptool package on Fedora).
    if command -v curl >/dev/null 2>&1; then
        CODE=$(curl -sS -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/ipp/print/konica206" 2>/dev/null || true)
        case "$CODE" in
            000|'') return 1 ;;
            *) return 0 ;;
        esac
    fi
    return 2
}

n=0
while [ "$n" -lt 10 ]; do
    if probe; then
        if command -v ipptool >/dev/null 2>&1 && [ -r "$TEST_FILE" ]; then
            echo "HEALTHY: $URL answered GetPrinterAttributes"
        else
            echo "HEALTHY (shallow HTTP probe only; ipptool not available)"
        fi
        exit 0
    fi
    n=$((n + 1))
    [ "$n" -lt 10 ] && sleep 1
done

echo "UNHEALTHY: $URL did not respond after 10 attempts" >&2
[ -n "${OUT:-}" ] && echo "$OUT" >&2
exit 1
