#!/bin/sh
# Install one read-only status page on a dedicated, service-worker-free port.

SCRIPT_DIR="${K2_HELPER_DIR:-/mnt/UDISK/helper-script}"
. "$SCRIPT_DIR/scripts/system.sh"

SOURCE="$SCRIPT_DIR/web/k2-status"
PY="${K2_STATUS_PY:-/usr/bin/python3}"
WORKER="$SCRIPT_DIR/scripts/k2_observability.py"
NGINX_PATCH="$SCRIPT_DIR/scripts/k2_status_nginx.py"
STATUS_URL="http://127.0.0.1:4410/status.json"

remove_owned_legacy_link() {
    target="$1"
    if [ -L "$target" ] && [ "$(readlink "$target" 2>/dev/null)" = "$SOURCE" ]; then
        rm -f "$target"
        echo "STATUS_HUB|INFO|removed obsolete same-origin link: $target"
    fi
}

endpoint_status() {
    "$PY" -B - "$STATUS_URL" <<'PYEOF'
import json
import sys
import urllib.request

url = sys.argv[1]
request = urllib.request.Request(url, headers={"Cache-Control": "no-cache"})
with urllib.request.urlopen(request, timeout=3) as response:
    payload = json.loads(response.read().decode("utf-8"))
    cache_control = response.headers.get("Cache-Control", "")
    if response.status != 200 or "no-store" not in cache_control:
        raise SystemExit(1)
    if not isinstance(payload, dict) or "printer" not in payload:
        raise SystemExit(2)
print("STATUS_HUB|OK|dedicated endpoint HTTP 200, no-store, valid JSON")
PYEOF
}

install_hub() {
    [ -f "$SOURCE/index.html" ] || {
        log_error "Missing $SOURCE/index.html"
        return 1
    }
    [ -f "$SOURCE/status.json" ] || {
        log_error "Missing $SOURCE/status.json"
        return 1
    }
    [ -f "$WORKER" ] || {
        log_error "Missing $WORKER"
        return 1
    }
    [ -f "$NGINX_PATCH" ] || {
        log_error "Missing $NGINX_PATCH"
        return 1
    }
    "$PY" -B "$WORKER" --selftest || return 1
    "$PY" -B "$NGINX_PATCH" install || return 1
    remove_owned_legacy_link /usr/share/fluidd/k2-status
    remove_owned_legacy_link /usr/share/mainsail/k2-status
    "$PY" -B "$WORKER" --capture-mesh || return 1
    endpoint_status || return 1
    mark_installed "k2_status_hub"
    log_success "K2 status page installed on dedicated port 4410 without restarting printer services."
    status_hub
}

status_hub() {
    result=0
    [ -f "$SOURCE/index.html" ] || result=1
    [ -f "$SOURCE/status.json" ] || result=1
    "$PY" -B "$NGINX_PATCH" check || result=1
    endpoint_status || result=1
    echo "STATUS_HUB_URL|Dedicated|http://PRINTER-IP:4410/"
    echo "STATUS_HUB_NOTE|Port 4410 avoids the Fluidd/Mainsail service-worker cache"
    echo "STATUS_HUB_NOTE|the same URL can be opened on the HelixScreen/K2Dash Raspberry Pi"
    return "$result"
}

refresh_hub() {
    "$PY" -B "$NGINX_PATCH" install || return 1
    "$PY" -B "$WORKER" --capture-mesh || return 1
    endpoint_status
}

remove_hub() {
    "$PY" -B "$NGINX_PATCH" remove || return 1
    remove_owned_legacy_link /usr/share/fluidd/k2-status
    remove_owned_legacy_link /usr/share/mainsail/k2-status
    mark_removed "k2_status_hub"
    log_success "Dedicated K2 status endpoint removed; reports were kept."
}

case "$1" in
    install) install_hub ;;
    status|"") status_hub ;;
    refresh) refresh_hub ;;
    remove) remove_hub ;;
    selftest) "$PY" -B "$WORKER" --selftest ;;
    *) echo "Usage: $0 {install|status|refresh|remove|selftest}"; exit 2 ;;
esac
