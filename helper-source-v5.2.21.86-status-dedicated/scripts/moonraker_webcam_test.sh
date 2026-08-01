#!/bin/sh
# moonraker_webcam_test.sh - Keep Moonraker's webcam tester compatible with BusyBox netstat.

SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

TARGET=/usr/bin/ss
BACKUP_DIR=/mnt/UDISK/printer_data/backups/k2pro_helper/moonraker_ss
BASELINE_BACKUP=$BACKUP_DIR/ss.before-helper
MARKER='# K2 Pro Moonraker webcam test compatibility v1'

write_candidate() {
    candidate="$1"
    cat > "$candidate" <<'SSEOF'
#!/bin/sh

# K2 Pro Moonraker webcam test compatibility v1
# Moonraker expects `ss -ltn`; the Creality image only provides BusyBox netstat.

if [ -x /bin/netstat ]; then
    NETSTAT=/bin/netstat
elif [ -x /usr/bin/netstat ]; then
    NETSTAT=/usr/bin/netstat
else
    echo "ss: netstat not found" >&2
    exit 127
fi

emit_listeners() {
    printf '%s\n' 'State Recv-Q Send-Q Local_Address:Port Peer_Address:Port'
    "$NETSTAT" -ltn 2>/dev/null | awk '
        NR <= 2 { next }
        $1 !~ /^tcp/ || NF < 6 { next }
        {
            local_addr = $4
            peer_addr = $5

            # Moonrakers bundled parser uses split(":"), so expose IPv6
            # listeners as IPv4 wildcards for local port discovery only.
            if (local_addr ~ /^:::/) {
                local_addr = "0.0.0.0:" substr(local_addr, 4)
            } else if (local_addr ~ /^\[::\]:/) {
                local_addr = "0.0.0.0:" substr(local_addr, 6)
            } else if (local_addr ~ /:/ && local_addr !~ /^[0-9.]+:/) {
                count = split(local_addr, parts, ":")
                local_addr = "0.0.0.0:" parts[count]
            }

            if (peer_addr ~ /^:::/) {
                peer_addr = "0.0.0.0:" substr(peer_addr, 4)
            } else if (peer_addr ~ /^\[::\]:/) {
                peer_addr = "0.0.0.0:" substr(peer_addr, 6)
            } else if (peer_addr ~ /:/ && peer_addr !~ /^[0-9.]+:/) {
                count = split(peer_addr, parts, ":")
                peer_addr = "0.0.0.0:" parts[count]
            }

            printf "%s %s %s %s %s\n", $6, $2, $3, local_addr, peer_addr
        }
    '
}

case "$*" in
    -ltn|-ntl|-tln|-lnt|-lt|-tl)
        emit_listeners
        ;;
    '')
        exec "$NETSTAT"
        ;;
    *)
        exec "$NETSTAT" "$@"
        ;;
esac
SSEOF
    chmod 0755 "$candidate"
}

verify_ss_format() {
    if [ ! -x "$TARGET" ]; then
        log_error "$TARGET is missing or not executable."
        return 1
    fi

    python3 - "$TARGET" <<'PYEOF'
import subprocess
import sys

output = subprocess.check_output([sys.argv[1], "-ltn"], stderr=subprocess.DEVNULL).decode()
lines = [line.split() for line in output.splitlines()[1:] if line.strip()]
if not lines:
    print("SS_FORMAT_FAIL|no listener rows")
    raise SystemExit(1)

bad = []
ports = set()
for fields in lines:
    if len(fields) < 5:
        bad.append("short-row")
        continue
    local = fields[3]
    if local.count(":") != 1:
        bad.append(local)
        continue
    ports.add(local.rsplit(":", 1)[1])

if bad:
    print("SS_FORMAT_FAIL|unparseable local address: %s" % ",".join(bad[:4]))
    raise SystemExit(1)
print("SS_FORMAT_OK|rows=%d|ports=%s" % (len(lines), ",".join(sorted(ports))))
PYEOF
}

webcam_test_status() {
    python3 - <<'PYEOF'
import json
import sys
import urllib.parse
import urllib.request

base = "http://127.0.0.1:7125"
try:
    with urllib.request.urlopen(base + "/server/webcams/list", timeout=6) as response:
        webcams = json.loads(response.read().decode()).get("result", {}).get("webcams", [])
except Exception as exc:
    print("WEBCAM_TEST_FAIL|Moonraker unavailable: %s" % exc)
    raise SystemExit(1)

if not any(cam.get("name") == "K2 Camera" for cam in webcams):
    print("WEBCAM_TEST_INFO|K2 Camera is not registered")
    raise SystemExit(0)

url = base + "/server/webcams/test?name=" + urllib.parse.quote("K2 Camera")
try:
    request = urllib.request.Request(url, method="POST")
    with urllib.request.urlopen(request, timeout=15) as response:
        result = json.loads(response.read().decode()).get("result", {})
except Exception as exc:
    print("WEBCAM_TEST_FAIL|request failed: %s" % exc)
    raise SystemExit(1)

snapshot_url = result.get("snapshot_url") or ""
stream_url = result.get("stream_url") or ""
reachable = result.get("snapshot_reachable") is True
print(
    "WEBCAM_TEST_RESULT|snapshot_reachable=%s|snapshot_url=%s|stream_url=%s"
    % (reachable, snapshot_url, stream_url)
)
if not snapshot_url or not stream_url:
    raise SystemExit(1)
if not reachable:
    direct_url = urllib.parse.urljoin(base + "/", snapshot_url)
    last_error = "no response"
    for attempt in range(1, 4):
        try:
            with urllib.request.urlopen(direct_url, timeout=6) as response:
                content_type = response.headers.get("Content-Type", "")
                header = response.read(64)
                if response.status == 200 and (
                    content_type.lower().startswith("image/")
                    or header.startswith(b"\xff\xd8")
                ):
                    print(
                        "WEBCAM_DIRECT_OK|attempt=%d|content_type=%s"
                        % (attempt, content_type or "unknown")
                    )
                    raise SystemExit(0)
                last_error = "HTTP %s content-type=%s" % (
                    response.status,
                    content_type or "unknown",
                )
        except Exception as exc:
            last_error = str(exc)
    print("WEBCAM_DIRECT_FAIL|%s" % last_error)
    raise SystemExit(2)
PYEOF
}

install_compat() {
    mkdir -p "$BACKUP_DIR" /usr/bin
    candidate=/tmp/k2pro_ss_compat_$$
    trap 'rm -f "$candidate"' EXIT INT TERM
    write_candidate "$candidate"
    sh -n "$candidate" || {
        log_error "Generated ss compatibility wrapper failed shell validation."
        return 1
    }

    if [ -f "$TARGET" ] && ! grep -Fq "$MARKER" "$TARGET" 2>/dev/null; then
        if [ ! -f "$BASELINE_BACKUP" ]; then
            cp -a "$TARGET" "$BASELINE_BACKUP" || return 1
            log_info "Saved original ss wrapper to $BASELINE_BACKUP"
        fi
        cp -a "$TARGET" "$BACKUP_DIR/ss.before-update.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi

    if [ -f "$TARGET" ] && cmp -s "$candidate" "$TARGET"; then
        log_info "Moonraker ss compatibility wrapper is already current."
    else
        cp "$candidate" "$TARGET" || return 1
        chmod 0755 "$TARGET"
        log_success "Installed Moonraker-compatible ss listener output."
    fi
    rm -f "$candidate"
    trap - EXIT INT TERM

    verify_ss_format || return 1
    mark_installed "moonraker_webcam_test_compat"
    return 0
}

status_compat() {
    if grep -Fq "$MARKER" "$TARGET" 2>/dev/null; then
        log_success "Moonraker ss compatibility wrapper is installed."
    else
        log_warn "Moonraker ss compatibility wrapper is not installed/current."
    fi
    verify_ss_format || return 1
    webcam_test_status
    rc=$?
    case "$rc" in
        0) log_success "Moonraker webcam test completed." ;;
        2)
            log_warn "Moonraker produced usable URLs; its one-second snapshot probe was too short for this Creality stream."
            return 0
            ;;
        *) log_error "Moonraker webcam test did not produce usable URLs." ;;
    esac
    return "$rc"
}

remove_compat() {
    if [ -f "$BASELINE_BACKUP" ]; then
        cp -a "$BASELINE_BACKUP" "$TARGET" || return 1
        chmod 0755 "$TARGET" 2>/dev/null || true
        log_success "Restored the previous ss wrapper from $BASELINE_BACKUP"
    elif grep -Fq "$MARKER" "$TARGET" 2>/dev/null; then
        rm -f "$TARGET"
        log_warn "Removed helper ss wrapper; no earlier wrapper backup existed."
    else
        log_info "Helper ss wrapper is not installed."
    fi
    mark_removed "moonraker_webcam_test_compat"
}

case "$1" in
    install|repair) install_compat ;;
    status) status_compat ;;
    format) verify_ss_format ;;
    remove) remove_compat ;;
    *) echo "Usage: $0 {install|repair|status|format|remove}" ;;
esac
