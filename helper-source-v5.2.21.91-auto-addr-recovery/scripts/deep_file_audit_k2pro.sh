#!/bin/sh
# deep_file_audit_k2pro.sh - read-only broad file/script/config audit for K2 Pro Combo
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

REPORT_DIR="$SCRIPT_DIR/reports"
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/deep_file_audit_$(date +%Y%m%d_%H%M%S).txt"
TMP_REPORT="/tmp/deep_file_audit_output.$$"
trap 'rm -f "$TMP_REPORT" /tmp/deep_audit_sh.err /tmp/deep_audit_py.err /tmp/deep_audit_py_files.$$ /tmp/deep_audit_json.out /tmp/deep_audit_includes.out /tmp/deep_audit_nginx.err /tmp/deep_audit_broken_links.$$' EXIT

ok=0
info=0
warn=0
fail=0

line() {
    state="$1"
    name="$2"
    detail="$3"
    case "$state" in
        OK) ok=$((ok + 1)) ;;
        INFO) info=$((info + 1)) ;;
        WARN) warn=$((warn + 1)) ;;
        FAIL) fail=$((fail + 1)) ;;
    esac
    printf "%-5s %-46s %s\n" "$state" "$name" "$detail"
}

run_audit() {
    echo "K2 Pro Combo deep file/script audit"
    echo "Safety: read-only only. No flash, heat, move, print, load, unload or CFS command is sent."
    date
    echo ""

    echo "Printer state"
    wget -qO- "http://127.0.0.1:7125/printer/objects/query?print_stats&webhooks&extruder&heater_bed&virtual_sdcard" || true
    echo ""
    echo ""

    echo "Shell syntax"
    for f in "$SCRIPT_DIR/helper.sh" "$SCRIPT_DIR"/scripts/*.sh "$SCRIPT_DIR/scripts/S98nozzle_camera_recover" /etc/init.d/S8* /etc/init.d/S9*; do
        [ -f "$f" ] || continue
        if sh -n "$f" 2>/tmp/deep_audit_sh.err; then
            line OK "$(basename "$f")" "$f"
        else
            line FAIL "$(basename "$f")" "$(cat /tmp/deep_audit_sh.err)"
        fi
    done
    echo ""

    echo "Python compile"
    py_list="/tmp/deep_audit_py_files.$$"
    find -L "$SCRIPT_DIR" /mnt/UDISK/printer_data/config -type f -name "*.py" 2>/dev/null > "$py_list"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if python3 - "$f" 2>/tmp/deep_audit_py.err <<'PYEOF'
from pathlib import Path
import sys
path = Path(sys.argv[1])
compile(path.read_text(errors="replace"), str(path), "exec")
PYEOF
        then
            line OK "$(basename "$f")" "$f"
        else
            line FAIL "$(basename "$f")" "$(cat /tmp/deep_audit_py.err)"
        fi
    done < "$py_list"
    rm -f "$py_list"
    echo ""

    echo "JSON and Creality data formats"
    python3 - <<'PYEOF' > /tmp/deep_audit_json.out
import json
from pathlib import Path

roots = [
    Path("/mnt/UDISK/helper-script"),
    Path("/mnt/UDISK/creality/userdata"),
    Path("/mnt/UDISK/creality/gui/config"),
    Path("/mnt/UDISK/printer_data/config"),
]
encrypted_names = {"user_data_not_deleted.json", "tb_info.json", "user_info.json"}
offset_names = {"upload_data_offset.json"}
jsonl_prefixes = ("pipe-", "statistic-", "print_list-")
ok = info = warn = fail = 0

def emit(state, name, detail):
    print(f"{state}|{name}|{detail}")

def classify(path):
    global ok, info, warn, fail
    name = path.name
    data = path.read_bytes()
    text = data.decode("utf-8", errors="ignore")
    if name in encrypted_names:
        if data:
            info += 1
            emit("INFO", name, f"Creality encrypted/private data, size={len(data)}, skipped JSON parse: {path}")
        else:
            warn += 1
            emit("WARN", name, f"Creality encrypted/private data is empty: {path}")
        return
    if name in offset_names:
        lines = [ln for ln in text.splitlines() if ln.strip()]
        if all("##" in ln for ln in lines) or not lines:
            info += 1
            emit("INFO", name, f"Creality offset text table, lines={len(lines)}: {path}")
        else:
            warn += 1
            emit("WARN", name, f"unexpected offset format: {path}")
        return
    if name.startswith(jsonl_prefixes):
        # Creality GUI files are not strict JSON documents. They are event streams
        # written as adjacent objects and may include padding/control bytes.
        event_count = text.count('"reqId"') + text.count("'reqId'")
        if event_count or text.lstrip("\x00\r\n\t ").startswith("{"):
            info += 1
            emit("INFO", name, f"Creality GUI event stream, approx_events={max(event_count, 1)}, size={len(data)}: {path}")
        elif not data:
            warn += 1
            emit("WARN", name, f"empty Creality GUI event stream: {path}")
        else:
            fail += 1
            emit("FAIL", name, f"unexpected Creality GUI event stream format: {path}")
        return
    try:
        json.loads(text)
        ok += 1
        emit("OK", name, f"valid JSON: {path}")
    except Exception as exc:
        fail += 1
        emit("FAIL", name, f"{exc}: {path}")

for root in roots:
    if not root.exists():
        continue
    for path in sorted(root.rglob("*.json")):
        classify(path)
print(f"JSON_SUMMARY|ok={ok}|info={info}|warn={warn}|fail={fail}")
PYEOF
    while IFS='|' read -r state name detail; do
        [ -n "$state" ] || continue
        if [ "$state" = "JSON_SUMMARY" ]; then
            echo "$state|$name"
            continue
        fi
        line "$state" "$name" "$detail"
    done < /tmp/deep_audit_json.out
    echo ""

    echo "Klipper include references"
    python3 - <<'PYEOF' > /tmp/deep_audit_includes.out
from pathlib import Path
import re
cfg = Path("/mnt/UDISK/printer_data/config/printer.cfg")
base = cfg.parent
fail = 0
if not cfg.exists():
    print("FAIL|printer.cfg|missing")
    raise SystemExit
for line_no, line in enumerate(cfg.read_text(errors="ignore").splitlines(), 1):
    match = re.match(r"\s*\[include\s+([^\]]+)\]", line)
    if not match:
        continue
    pattern = match.group(1).strip()
    matches = list(base.glob(pattern))
    if matches:
        print(f"OK|include line {line_no}|{pattern} -> {len(matches)} file(s)")
    else:
        fail += 1
        print(f"FAIL|include line {line_no}|missing: {pattern}")
print(f"INCLUDE_SUMMARY|fail={fail}")
PYEOF
    while IFS='|' read -r state name detail; do
        [ -n "$state" ] || continue
        if [ "$state" = "INCLUDE_SUMMARY" ]; then
            echo "$state|$name"
        else
            line "$state" "$name" "$detail"
        fi
    done < /tmp/deep_audit_includes.out
    echo ""

    echo "Executable permissions"
    for f in "$SCRIPT_DIR/go2rtc" "$SCRIPT_DIR/helper.sh" "$SCRIPT_DIR"/scripts/*.sh "$SCRIPT_DIR/scripts/S98nozzle_camera_recover" /etc/init.d/S8* /etc/init.d/S9*; do
        [ -e "$f" ] || continue
        case "$f" in
            *.bak|*.bak-*|*.orig|*.orig.*)
                line INFO "$(basename "$f")" "backup file, execute bit not required: $f"
                continue
                ;;
        esac
        if [ -x "$f" ]; then
            line OK "$(basename "$f")" "executable: $f"
        else
            line FAIL "$(basename "$f")" "not executable: $f"
        fi
    done
    echo ""

    echo "Broken symlinks"
    broken_links="/tmp/deep_audit_broken_links.$$"
    find "$SCRIPT_DIR" /mnt/UDISK/printer_data/config /etc/rc.d /etc/init.d -xtype l 2>/dev/null > "$broken_links"
    if [ ! -s "$broken_links" ]; then
        line OK "broken symlinks" "none"
    else
        while IFS= read -r item; do
            [ -n "$item" ] || continue
            line FAIL "broken symlink" "$item"
        done < "$broken_links"
    fi
    echo ""

    echo "Nginx config"
    if nginx -t -c /etc/nginx/nginx.conf 2>/tmp/deep_audit_nginx.err; then
        line OK "nginx.conf" "syntax ok"
    else
        line FAIL "nginx.conf" "$(cat /tmp/deep_audit_nginx.err)"
    fi
    echo ""

    echo "Recent severe logs"
    for f in /mnt/UDISK/printer_data/logs/moonraker.log /mnt/UDISK/printer_data/logs/klippy.log /tmp/camera_startup.log /tmp/go2rtc.log /tmp/watchdog.log; do
        [ -f "$f" ] || continue
        hits=$(tail -1000 "$f" | grep -Ei "traceback|fatal|panic|segmentation|permission denied|no such file|bad gateway|connection refused" | grep -Eiv "JSON-RPC Request Error: 400|utils\\.ServerError: No data for argument: value|raise ServerError\\(f\"No data for argument|^Traceback \\(most recent call last\\):?$" | wc -l | awk '{print $1}')
        if [ "$hits" -eq 0 ]; then
            line OK "$(basename "$f")" "no severe hits in last 1000 lines"
        else
            line WARN "$(basename "$f")" "severe-pattern hits=$hits; inspect below"
            tail -1000 "$f" | grep -Ei "traceback|fatal|panic|segmentation|permission denied|no such file|bad gateway|connection refused" | grep -Eiv "JSON-RPC Request Error: 400|utils\\.ServerError: No data for argument: value|raise ServerError\\(f\"No data for argument|^Traceback \\(most recent call last\\):?$" | tail -20
        fi
    done
    echo ""

    echo "Summary"
    printf "OK=%s INFO=%s WARN=%s FAIL=%s\n" "$ok" "$info" "$warn" "$fail"
    printf "REPORT=%s\n" "$REPORT"
    [ "$fail" -eq 0 ]
}

if run_audit > "$TMP_REPORT"; then
    audit_rc=0
else
    audit_rc=$?
fi
cat "$TMP_REPORT" | tee "$REPORT"
exit "$audit_rc"
