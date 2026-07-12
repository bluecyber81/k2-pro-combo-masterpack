#!/bin/sh
# health.sh - non-destructive helper, camera, CFS/BOX and log checks

SCRIPT_DIR=/mnt/UDISK/helper-script
CONFIG_DIR=/mnt/UDISK/printer_data/config
LOGS_DIR=/mnt/UDISK/printer_data/logs
INSTALLED_FILE=$SCRIPT_DIR/.installed

. "$SCRIPT_DIR/scripts/system.sh"

OK_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

ok() {
    OK_COUNT=$((OK_COUNT + 1))
    printf "%b\n" "${GREEN}[OK]${NC} $1"
}

warn() {
    WARN_COUNT=$((WARN_COUNT + 1))
    printf "%b\n" "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo "[INFO] $1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf "%b\n" "${RED}[FAIL]${NC} $1"
}

section() {
    echo ""
    echo "== $1 =="
}

proc_count() {
    expected="$1"
    count=0
    for proc in /proc/[0-9]*; do
        [ -r "$proc/cmdline" ] || continue
        cmd="$(tr '\000' ' ' < "$proc/cmdline" 2>/dev/null)" || continue
        case "$cmd" in
            "$expected"|"$expected "*) count=$((count + 1)) ;;
        esac
    done
    echo "$count"
}

proc_count_contains() {
    expected="$1"
    count=0
    for proc in /proc/[0-9]*; do
        [ -r "$proc/cmdline" ] || continue
        cmd="$(tr '\000' ' ' < "$proc/cmdline" 2>/dev/null)" || continue
        case "$cmd" in
            *"$expected"*) count=$((count + 1)) ;;
        esac
    done
    echo "$count"
}

http_check() {
    label="$1"
    url="$2"
    python3 - "$label" "$url" << 'PYEOF'
import sys
import time
import urllib.request

label, url = sys.argv[1], sys.argv[2]
last_error = None
for attempt in range(1, 3):
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            sample = response.read(1024)
            print("%s|%s|%s|%s|attempt=%s" % (
                label,
                response.status,
                response.headers.get("content-type", ""),
                len(sample),
                attempt,
            ))
            sys.exit(0)
    except Exception as exc:
        last_error = exc
        time.sleep(1)
print("%s|ERROR|%s|0" % (label, last_error))
sys.exit(1)
PYEOF
}

check_helper_files() {
    section "Helper files"
    [ -x "$SCRIPT_DIR/helper.sh" ] && ok "helper.sh is executable" || fail "helper.sh missing or not executable"
    [ -d "$SCRIPT_DIR/scripts" ] && ok "scripts directory exists" || fail "scripts directory missing"
    [ -x "$SCRIPT_DIR/scripts/S98nozzle_camera_recover" ] && ok "S98nozzle_camera_recover is executable" || warn "S98nozzle_camera_recover missing or not executable"
    [ -f "$INSTALLED_FILE" ] && ok ".installed exists" || warn ".installed missing"

    bad=0
    for f in "$SCRIPT_DIR/helper.sh" "$SCRIPT_DIR"/scripts/*.sh "$SCRIPT_DIR/scripts/S98nozzle_camera_recover"; do
        [ -f "$f" ] || continue
        if ! sh -n "$f"; then
            fail "Shell syntax failed: $f"
            bad=1
        fi
    done
    [ "$bad" -eq 0 ] && ok "Shell syntax check passed"

    py_list=/tmp/helper_py_files.$$
    find -L "$SCRIPT_DIR" -maxdepth 3 -type f -name "*.py" 2>/dev/null > "$py_list"
    if [ -s "$py_list" ]; then
        if python3 - "$py_list" > /tmp/helper_py_compile.log 2>&1 << 'PYEOF'; then
import pathlib
import sys

bad = []
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    files = [line.strip() for line in handle if line.strip()]
for name in files:
    path = pathlib.Path(name)
    try:
        compile(path.read_text(), str(path), "exec")
    except Exception as exc:
        bad.append(f"{path}: {exc}")
if bad:
    print("\n".join(bad))
    raise SystemExit(1)
PYEOF
            ok "Python helper compile check passed"
        else
            fail "Python helper compile check failed; see /tmp/helper_py_compile.log"
        fi
    fi
    rm -f "$py_list"

    echo ""
    sh "$SCRIPT_DIR/scripts/system.sh" show_installed
}

check_camera() {
    section "Camera"
    if [ ! -x /etc/rc.d/S99camera ]; then
        if [ -f "$INSTALLED_FILE" ] && grep -q "^camera_support$" "$INSTALLED_FILE" 2>/dev/null; then
            fail "S99camera helper service missing although camera_support is marked installed"
        else
            warn "Camera support is not installed; skipping camera bridge checks"
        fi
        return
    fi

    if [ -x "$SCRIPT_DIR/go2rtc" ]; then
        ok "go2rtc binary is executable"
    else
        fail "go2rtc binary is missing or not executable"
    fi

    /etc/rc.d/S99camera status 2>/dev/null || warn "S99camera status returned non-zero"

    go2rtc_count=$(proc_count "$SCRIPT_DIR/go2rtc")
    k2rtc_count=$(proc_count_contains "$SCRIPT_DIR/k2rtc.py")
    watchdog_count=$(proc_count_contains "$SCRIPT_DIR/camera_watchdog.py")

    [ "$go2rtc_count" = "1" ] && ok "one go2rtc process" || fail "expected one go2rtc process, found $go2rtc_count"
    if grep -q "#format=creality" "$SCRIPT_DIR/go2rtc.yaml" 2>/dev/null; then
        [ "$k2rtc_count" = "0" ] && ok "direct go2rtc mode without k2rtc.py process" || fail "expected no k2rtc.py process in direct mode, found $k2rtc_count"
    else
        [ "$k2rtc_count" = "1" ] && ok "one k2rtc.py process" || fail "expected one k2rtc.py process, found $k2rtc_count"
    fi
    [ "$watchdog_count" = "1" ] && ok "one camera_watchdog.py process" || fail "expected one camera_watchdog.py process, found $watchdog_count"

    netstat -lnt 2>/dev/null | grep -q ':1984 ' && ok "go2rtc listens on 1984" || fail "go2rtc port 1984 not listening"

    if grep -q "location /go2rtc/" /etc/nginx/nginx.conf 2>/dev/null && \
       grep -q "listen 4408" /etc/nginx/nginx.conf 2>/dev/null && \
       grep -q "listen 4409" /etc/nginx/nginx.conf 2>/dev/null; then
        ok "nginx go2rtc proxy blocks exist for Fluidd/Mainsail"
    else
        fail "nginx go2rtc proxy blocks missing or incomplete"
    fi

    for item in \
        "go2rtc streams|http://127.0.0.1:1984/api/streams" \
        "go2rtc direct frame|http://127.0.0.1:1984/api/frame.jpeg?src=k2camera" \
        "Fluidd go2rtc frame proxy|http://127.0.0.1:4408/go2rtc/api/frame.jpeg?src=k2camera" \
        "Mainsail go2rtc frame proxy|http://127.0.0.1:4409/go2rtc/api/frame.jpeg?src=k2camera" \
        "Mainsail go2rtc WebRTC page|http://127.0.0.1:4409/go2rtc/stream.html?src=k2camera&mode=webrtc"
    do
        label=${item%%|*}
        url=${item#*|}
        if out=$(http_check "$label" "$url"); then
            ok "$out"
        else
            fail "$out"
        fi
    done

    python3 - << 'PYEOF'
import json
import sys
import urllib.request

failed = 0
try:
    with urllib.request.urlopen("http://127.0.0.1:7125/server/webcams/list", timeout=6) as response:
        webcams = json.loads(response.read().decode()).get("result", {}).get("webcams", [])
    print("WEBCAM_COUNT|%s" % len(webcams))
    k2 = [cam for cam in webcams if cam.get("name") == "K2 Camera"]
    if not k2:
        print("WEBCAM_K2|MISSING")
        failed = 1
    else:
        cam = k2[0]
        print("WEBCAM_K2_SERVICE|%s" % cam.get("service"))
        print("WEBCAM_K2_ENABLED|%s" % cam.get("enabled"))
        print("WEBCAM_K2_ICON|%s" % cam.get("icon"))
        print("WEBCAM_K2_TARGET_FPS|%s" % cam.get("target_fps"))
        print("WEBCAM_K2_TARGET_FPS_IDLE|%s" % cam.get("target_fps_idle"))
        print("WEBCAM_K2_ASPECT_RATIO|%s" % cam.get("aspect_ratio"))
        print("WEBCAM_K2_STREAM|%s" % cam.get("stream_url"))
        print("WEBCAM_K2_SNAPSHOT|%s" % cam.get("snapshot_url"))
        if cam.get("enabled") is not True:
            failed = 1
        if cam.get("icon") not in ("mdiWebcam", "mdi-webcam", None):
            failed = 1
        if cam.get("aspect_ratio") not in ("16:9", None):
            failed = 1
        if cam.get("service") != "webrtc-go2rtc":
            failed = 1
        if "k2camera" not in str(cam.get("stream_url", "")):
            failed = 1
        if "k2camera" not in str(cam.get("snapshot_url", "")):
            failed = 1
        try:
            if int(cam.get("target_fps") or 0) < 15:
                failed = 1
        except Exception:
            failed = 1
        try:
            idle_fps = cam.get("target_fps_idle")
            if idle_fps is not None and int(idle_fps or 0) < 15:
                print("WEBCAM_K2_IDLE_FPS_LOW|%s" % idle_fps)
                failed = 1
        except Exception:
            print("WEBCAM_K2_IDLE_FPS_LOW|%s" % cam.get("target_fps_idle"))
            failed = 1
except Exception as exc:
    print("WEBCAM_API_ERROR|%s" % exc)
    failed = 1

sys.exit(failed)
PYEOF
    webcam_rc=$?
    [ "$webcam_rc" -eq 0 ] && ok "Moonraker webcam entry is K2/Mainsail compatible" || fail "Moonraker webcam entry is missing or not K2/Mainsail compatible"

    if [ "$(get_sn_mac.sh model 2>/dev/null)" = "F012" ]; then
        python3 - << 'PYEOF'
import glob
import json
import subprocess
import sys
from pathlib import Path

try:
    raw = subprocess.check_output(["ubus", "call", "camera", "status"], stderr=subprocess.DEVNULL).decode()
    status = json.loads(raw).get("cameras", {})
except Exception as exc:
    print("NOZZLE_AI_CAMERA|ERROR|%s" % exc)
    sys.exit(1)

main_online = status.get("camera_main", {}).get("online")
sub_online = status.get("camera_sub", {}).get("online")
patterns = [
    "/dev/v4l/by-id/*sub*",
    "/dev/v4l/by-path/*sub*",
    "/dev/v4l/by-id/*nozzle*",
    "/dev/v4l/by-path/*nozzle*",
]
sub_nodes = sorted({p for pat in patterns for p in glob.glob(pat) if Path(p).exists()})
video_nodes = sorted(str(p) for p in Path("/dev").glob("video*"))
print("CAMERA_MAIN_ONLINE|%s" % main_online)
print("NOZZLE_AI_CAMERA_ONLINE|%s" % sub_online)
print("NOZZLE_AI_CAMERA_SUB_NODES|%s" % (" ".join(sub_nodes) if sub_nodes else "missing"))
print("NOZZLE_AI_CAMERA_VIDEO_NODES|%s" % (" ".join(video_nodes) if video_nodes else "missing"))
if sub_online != 1 or not sub_nodes or not video_nodes:
    sys.exit(2)
sys.exit(0)
PYEOF
        rc=$?
        if [ "$rc" -eq 0 ]; then
            ok "Nozzle AI camera is online"
        elif [ "$rc" -eq 2 ]; then
            info "Nozzle AI camera is offline/standby; Creality may enable it on demand, run nozzle camera recover only if AI calibration fails"
        else
            warn "Nozzle AI camera status query failed; main camera checks stay authoritative, run nozzle USB diagnose only if AI/flow/first-layer fails"
        fi
        if [ -x "$SCRIPT_DIR/scripts/nozzle_camera_recover.sh" ]; then
            sh "$SCRIPT_DIR/scripts/nozzle_camera_recover.sh" diagnose-compact 2>/dev/null | sed 's/^/[INFO] /'
        fi
    fi
}

check_timelapse_recover() {
    section "Creality Timelapse Recover"
    if [ ! -f "$INSTALLED_FILE" ] || ! grep -q "^creality_timelapse_recover$" "$INSTALLED_FILE" 2>/dev/null; then
        if [ -x /etc/rc.d/S99timelapse_recover ]; then
            warn "S99timelapse_recover exists but feature is not marked installed"
        else
            warn "Creality timelapse recover is not installed; skipping"
        fi
        return
    fi

    [ -x /etc/rc.d/S99timelapse_recover ] && ok "S99timelapse_recover service exists" || fail "S99timelapse_recover service missing"
    recover_count=$(proc_count_contains "$SCRIPT_DIR/creality_timelapse_recover.py")
    [ "$recover_count" = "1" ] && ok "one creality_timelapse_recover daemon process" || fail "expected one creality_timelapse_recover daemon, found $recover_count"

    if [ -x /etc/rc.d/S99timelapse_recover ]; then
        /etc/rc.d/S99timelapse_recover status >/tmp/timelapse_recover_status.log 2>&1 && ok "timelapse recover status command succeeded" || fail "timelapse recover status command failed"
        if grep -q '"delay_image_switch": 1' /tmp/timelapse_recover_status.log 2>/dev/null; then
            ok "Creality delay_image switch is enabled"
        else
            warn "Creality delay_image switch is not reported as enabled"
        fi
    fi

    python3 - << 'PYEOF'
import json
from pathlib import Path

info = Path('/mnt/UDISK/creality/userdata/delay_image/delay_image_info.json')
if not info.exists():
    print('ERROR|delay_image_info.json missing')
    raise SystemExit(1)
data = json.loads(info.read_text())
items = data.get('list', [])
missing = []
for item in items:
    for key in ('video', 'cover'):
        value = item.get(key)
        if value and not Path(value).exists():
            missing.append(f"{key}:{value}")
print(f"COUNT|{len(items)}")
if missing:
    print("MISSING|" + ";".join(missing))
    raise SystemExit(1)
PYEOF
    rc=$?
    [ "$rc" -eq 0 ] && ok "Creality delay_image list files exist" || fail "Creality delay_image list has missing files"
}

check_frontends() {
    section "Fluidd / Mainsail"

    if [ -f /usr/share/fluidd/.version ]; then
        fluidd_version=$(cat /usr/share/fluidd/.version 2>/dev/null)
        ok "Fluidd installed: $fluidd_version"
    else
        fail "Fluidd version file missing: /usr/share/fluidd/.version"
    fi

    if [ -f /usr/share/mainsail/.version ]; then
        mainsail_version=$(cat /usr/share/mainsail/.version 2>/dev/null)
        ok "Mainsail installed: $mainsail_version"
    else
        fail "Mainsail version file missing: /usr/share/mainsail/.version"
    fi

    for item in \
        "Fluidd UI|http://127.0.0.1:4408/" \
        "Mainsail UI|http://127.0.0.1:4409/"
    do
        label=${item%%|*}
        url=${item#*|}
        if out=$(http_check "$label" "$url"); then
            ok "$out"
        else
            fail "$out"
        fi
    done

    python3 - << 'PYEOF'
import json
import sys
import urllib.parse
import urllib.request

failed = 0

def fetch(path, timeout=8):
    with urllib.request.urlopen("http://127.0.0.1:7125" + path, timeout=timeout) as response:
        return response.status, response.read()

for label, path in [
    ("SENSORS_LIST", "/server/sensors/list"),
    ("TIMELAPSE_SETTINGS", "/machine/timelapse/get_settings"),
    ("PERIPHERALS_CANBUS", "/machine/peripherals/canbus"),
    ("DEVICE_POWER_DEVICES", "/machine/device_power/devices"),
    ("UPDATE_STATUS_PASSIVE", "/machine/update/status"),
]:
    try:
        status, body = fetch(path, timeout=10)
        json.loads(body.decode() or "{}")
        print("%s|OK|%s" % (label, status))
    except Exception as exc:
        print("%s|ERROR|%s" % (label, exc))
        failed = 1

try:
    status, body = fetch("/server/files/list?root=gcodes", timeout=10)
    result = json.loads(body.decode()).get("result", [])
    gcodes = [
        item.get("path") or item.get("filename")
        for item in result
        if (item.get("path") or item.get("filename") or "").lower().endswith((".gcode", ".gcode.gz"))
    ]
    if gcodes:
        name = gcodes[0]
        status, body = fetch("/server/files/metascan?filename=" + urllib.parse.quote(name), timeout=20)
        parsed = json.loads(body.decode()).get("result", {})
        print("METASCAN|OK|%s|thumbnails=%s" % (name, len(parsed.get("thumbnails", []) or [])))
    else:
        print("METASCAN|SKIP|no gcode file in gcodes root")
except Exception as exc:
    print("METASCAN|ERROR|%s" % exc)
    failed = 1

sys.exit(failed)
PYEOF
    rc=$?
    [ "$rc" -eq 0 ] && ok "Frontend compatibility API checks passed" || fail "Frontend compatibility API checks failed"

    python3 - << 'PYEOF'
import json
import sys
import urllib.request

failed = 0
try:
    with urllib.request.urlopen("http://127.0.0.1:7125/server/database/item?namespace=mainsail", timeout=6) as response:
        data = json.loads(response.read().decode()).get("result", {}).get("value", {})
    dash = data.get("dashboard", {}) or {}
    layout1 = dash.get("desktopLayout1", []) or []
    layout2 = dash.get("desktopLayout2", []) or []
    panels = layout1 + layout2
    visible = {panel.get("name"): panel.get("visible") for panel in panels if isinstance(panel, dict)}
    print("MAINSAIL_LANGUAGE|%s" % data.get("general", {}).get("language"))
    print("MAINSAIL_INIT_VERSION|%s" % data.get("initVersion"))
    print("MAINSAIL_WEBCAM_PANEL|%s" % visible.get("webcam"))
    print("MAINSAIL_SPOOLMAN_PANEL|%s" % visible.get("spoolman"))
    if visible.get("webcam") is not True:
        failed = 1
    if visible.get("spoolman") is not True:
        failed = 1
except Exception as exc:
    print("MAINSAIL_DB_ERROR|%s" % exc)
    failed = 1
sys.exit(failed)
PYEOF
    mainsail_db_rc=$?
    [ "$mainsail_db_rc" -eq 0 ] && ok "Mainsail dashboard is K2 Pro Combo friendly" || warn "Mainsail dashboard DB does not show webcam/spoolman panels as visible"

    python3 - << 'PYEOF'
import asyncio
import json
import sys

from tornado.httpclient import HTTPRequest
from tornado.websocket import websocket_connect

checks = [
    ("PRINTER_INFO_WS", "printer.info", {}),
    ("OBJECTS_LIST_WS", "printer.objects.list", {}),
    ("OBJECTS_QUERY_WS", "printer.objects.query", {"objects": {"webhooks": None, "print_stats": None}}),
    ("SERVER_INFO_WS", "server.info", {}),
]

async def request(ws, label, method, params, req_id):
    await ws.write_message(json.dumps({
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "id": req_id,
    }))
    for _ in range(20):
        raw = await ws.read_message()
        if raw is None:
            raise RuntimeError("websocket closed")
        msg = json.loads(raw)
        if msg.get("id") != req_id:
            continue
        if "error" in msg:
            raise RuntimeError(msg["error"])
        print("%s|OK|%s" % (label, method))
        return
    raise RuntimeError("no response for %s" % method)

async def main():
    ws = await websocket_connect(
        HTTPRequest("ws://127.0.0.1:7125/websocket", request_timeout=10))
    try:
        for req_id, (label, method, params) in enumerate(checks, 1):
            await request(ws, label, method, params, req_id)
    finally:
        ws.close()

try:
    asyncio.get_event_loop().run_until_complete(main())
except Exception as exc:
    print("WEBSOCKET_COMPAT|ERROR|%s" % exc)
    sys.exit(1)
PYEOF
    rc=$?
    [ "$rc" -eq 0 ] && ok "Frontend WebSocket compatibility checks passed" || fail "Frontend WebSocket compatibility checks failed"
}

check_spoolman_sync() {
    section "Spoolman CFS Sync"
    if ! is_installed "spoolman_cfs_sync" && [ ! -x /etc/init.d/S99spoolman_cfs_sync ] && [ ! -x /etc/rc.d/S99spoolman_cfs_sync ]; then
        info "Spoolman CFS sync is not installed"
        return
    fi

    [ -x "$SCRIPT_DIR/spoolman_cfs_sync.py" ] && ok "Spoolman CFS sync worker is executable" || fail "Spoolman CFS sync worker missing or not executable"

    map_state="missing"
    map_ids_1_to_4="False"
    if [ -f "$SCRIPT_DIR/spoolman_cfs_map.json" ]; then
        ok "Spoolman CFS active slot map exists"
        map_report=$(python3 - "$SCRIPT_DIR/spoolman_cfs_map.json" << 'PYEOF'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except Exception as exc:
    print("state=invalid")
    print("ids_1_to_4=False")
    print("detail=%s" % exc)
    raise SystemExit(0)
slots = ["T1A", "T1B", "T1C", "T1D"]
values = {slot: data.get(slot) for slot in slots}
enabled = data.get("enabled")
ids_1_to_4 = all(str(values.get(slot)) == str(idx) for idx, slot in enumerate(slots, 1))
real = all(str(values.get(slot) or "").isdigit() and int(str(values.get(slot))) > 0 for slot in slots)
if enabled is False:
    state = "disabled"
elif enabled is True and real:
    state = "enabled"
elif enabled is True:
    state = "incomplete"
elif real:
    state = "legacy-enabled"
else:
    state = "disabled" if enabled is False else "incomplete"
print("state=%s" % state)
print("ids_1_to_4=%s" % ids_1_to_4)
print("detail=enabled=%s slots=%s" % (enabled, ",".join("%s:%s" % (slot, values.get(slot)) for slot in slots)))
PYEOF
)
        printf "%s\n" "$map_report" | sed 's/^/SPOOLMAN_MAP|/'
        map_state=$(printf "%s\n" "$map_report" | sed -n 's/^state=//p' | head -1)
        map_ids_1_to_4=$(printf "%s\n" "$map_report" | sed -n 's/^ids_1_to_4=//p' | head -1)
        [ "$map_ids_1_to_4" = "True" ] && info "Spoolman CFS slot map uses IDs 1-4; live Spoolman can use these as real IDs"
        case "$map_state" in
            enabled)
                ok "Spoolman CFS slot map is enabled and all T1A/T1B/T1C/T1D IDs are positive"
                ;;
            legacy-enabled)
                ok "Spoolman CFS slot map is a legacy active map with complete positive IDs"
                ;;
            disabled)
                ok "Spoolman CFS slot map is disabled safe-state; it will not change active spools"
                ;;
            incomplete)
                warn "Spoolman CFS slot map is incomplete; sync will skip unmapped slots"
                ;;
            invalid)
                fail "Spoolman CFS slot map JSON is invalid"
                ;;
            *)
                warn "Spoolman CFS slot map state is unclear: ${map_state:-unknown}"
                ;;
        esac
    else
        if [ -f "$SCRIPT_DIR/spoolman_cfs_map.example.json" ]; then
            ok "No active Spoolman CFS map is bundled/created; existing printer maps are preserved, example map is available"
        else
            warn "Spoolman CFS slot map missing and no example map found"
        fi
    fi

    service=""
    [ -x /etc/init.d/S99spoolman_cfs_sync ] && service=/etc/init.d/S99spoolman_cfs_sync
    [ -z "$service" ] && [ -x /etc/rc.d/S99spoolman_cfs_sync ] && service=/etc/rc.d/S99spoolman_cfs_sync
    if [ -n "$service" ]; then
        "$service" status >/tmp/spoolman_cfs_sync_status.txt 2>&1 || true
        cat /tmp/spoolman_cfs_sync_status.txt
        if grep -q "^running:" /tmp/spoolman_cfs_sync_status.txt; then
            ok "Spoolman CFS sync service is running"
        elif [ "$map_state" = "disabled" ] || [ "$map_state" = "missing" ]; then
            ok "Spoolman CFS sync service is not running because the map is disabled/missing safe-state"
        else
            warn "Spoolman CFS sync service is installed but not running"
        fi
        rm -f /tmp/spoolman_cfs_sync_status.txt
    else
        warn "Spoolman CFS sync init service missing"
    fi

    python3 - << 'PYEOF'
import json
import sys
import urllib.request

failed = 0
try:
    with urllib.request.urlopen("http://127.0.0.1:7125/server/spoolman/status", timeout=6) as response:
        data = json.loads(response.read().decode()).get("result", {})
    print("SPOOLMAN_CONNECTED|%s" % data.get("spoolman_connected"))
    print("SPOOLMAN_ACTIVE_SPOOL|%s" % data.get("spool_id"))
    if not data.get("spoolman_connected"):
        failed = 1
except Exception as exc:
    print("SPOOLMAN_STATUS_ERROR|%s" % exc)
    failed = 1
sys.exit(failed)
PYEOF
    spoolman_rc=$?
    [ "$spoolman_rc" -eq 0 ] && ok "Moonraker Spoolman connection is healthy" || warn "Moonraker Spoolman connection is not healthy"
}

check_firmware() {
    section "Firmware / System"

    if [ -x /etc/ota_bin/get_ota_current_version.sh ]; then
        ota_version=$(/etc/ota_bin/get_ota_current_version.sh 2>/dev/null)
        [ -n "$ota_version" ] && ok "OTA firmware version: $ota_version" || warn "OTA firmware version command returned empty value"
    else
        warn "OTA firmware version helper missing: /etc/ota_bin/get_ota_current_version.sh"
        ota_version=""
    fi
    if [ "$ota_version" = "1.1.6.3" ]; then
        ok "Firmware matches the 2026-07-07 K2 Pro Combo reference: $ota_version"
    elif [ -n "$ota_version" ]; then
        info "Firmware differs from reference 1.1.6.3: $ota_version; informational only unless release review says otherwise"
    fi

    if [ -f /mnt/UDISK/creality/userdata/config/system_version.json ]; then
        python3 - << 'PYEOF'
import json
from pathlib import Path

path = Path("/mnt/UDISK/creality/userdata/config/system_version.json")
data = json.loads(path.read_text())
print("SYS_VERSION|%s" % data.get("sys_version", ""))
print("HW_VERSION|%s" % data.get("hw_version", ""))
print("APP_VERSION|%s" % data.get("app_version", ""))
PYEOF
        hw_version=$(python3 - << 'PYEOF'
import json
from pathlib import Path
print(json.loads(Path("/mnt/UDISK/creality/userdata/config/system_version.json").read_text()).get("hw_version", ""))
PYEOF
)
        [ "$hw_version" = "CR0CN200400C10" ] && ok "Hardware version matches K2 Pro/F012 family: $hw_version" || warn "Unexpected hardware version: $hw_version"
    else
        warn "system_version.json not found"
    fi

    if [ -n "$ota_version" ] && ls "/mnt/UDISK/"*"${ota_version}"*.img >/dev/null 2>&1; then
        ok "Firmware image for current version is present on UDISK"
    elif [ -n "$ota_version" ]; then
        info "No local firmware image found on UDISK for current version $ota_version; runtime firmware is still current"
    fi
}

check_moonraker() {
    section "Moonraker"

    active_conf=""
    if [ -f /etc/init.d/moonraker ]; then
        active_conf=$(grep "^CONF=" /etc/init.d/moonraker 2>/dev/null | head -1 | cut -d= -f2)
    fi
    [ -n "$active_conf" ] || active_conf="/usr/share/moonraker/moonraker.conf"
    if [ "$active_conf" = "$CONFIG_DIR/moonraker.conf" ]; then
        ok "Moonraker startup uses UDISK wrapper config"
    else
        warn "Moonraker startup config is $active_conf, expected $CONFIG_DIR/moonraker.conf for helper extensions"
    fi

    if [ -f /usr/share/moonraker/moonraker.conf ]; then
        if grep -Eq "^[[:space:]]*queue_gcode_uploads:[[:space:]]*True[[:space:]]*$" /usr/share/moonraker/moonraker.conf 2>/dev/null; then
            ok "Moonraker queue_gcode_uploads is enabled for G-code metadata scans"
        elif grep -Eq "^[[:space:]]*queue_gcode_uploads:[[:space:]]*False[[:space:]]*$" /usr/share/moonraker/moonraker.conf 2>/dev/null; then
            warn "Moonraker queue_gcode_uploads is disabled; Fluidd/Mainsail may show missing G-code preview/metadata"
        else
            warn "Moonraker queue_gcode_uploads setting was not found"
        fi

        if grep -Eq "^[[:space:]]*enable_object_processing:[[:space:]]*True[[:space:]]*$" /usr/share/moonraker/moonraker.conf 2>/dev/null; then
            ok "Moonraker object processing is enabled for exclude-object and G-code object metadata"
        elif grep -Eq "^[[:space:]]*enable_object_processing:[[:space:]]*False[[:space:]]*$" /usr/share/moonraker/moonraker.conf 2>/dev/null; then
            warn "Moonraker object processing is disabled; Fluidd/Mainsail may miss object/progress metadata"
        else
            warn "Moonraker enable_object_processing setting was not found"
        fi
    else
        fail "Moonraker stock config missing: /usr/share/moonraker/moonraker.conf"
    fi

    python3 - << 'PYEOF'
import json
import sys
import urllib.request

failed = 0
try:
    with urllib.request.urlopen("http://127.0.0.1:7125/server/info", timeout=8) as response:
        info = json.loads(response.read().decode()).get("result", {})
    print("STATE|%s" % info.get("klippy_state"))
    print("FAILED|%s" % info.get("failed_components"))
    print("WARNINGS|%s" % info.get("warnings"))
    print("UPDATE_MANAGER|%s" % ("update_manager" in info.get("components", [])))
    if info.get("failed_components"):
        failed = 1
except Exception as exc:
    print("ERROR|server/info|%s" % exc)
    failed = 1

try:
    with urllib.request.urlopen("http://127.0.0.1:7125/machine/update/status", timeout=10) as response:
        status = json.loads(response.read().decode()).get("result", {})
    print("UPDATE_BUSY|%s" % status.get("busy"))
    keys = sorted(status.get("version_info", {}).keys())
    print("UPDATE_KEYS|%s" % ",".join(keys))
    messages = []
    for name, data in status.get("version_info", {}).items():
        messages.extend(data.get("git_messages", [])[:2])
    if messages:
        print("VENDOR_UPDATE_WARN|Creality zip/vendor tree produces git validation warnings; do not update core Klipper/Moonraker here.")
except Exception as exc:
    print("ERROR|update/status|%s" % exc)
    failed = 1

sys.exit(failed)
PYEOF
    rc=$?
    [ "$rc" -eq 0 ] && ok "Moonraker API checks passed" || fail "Moonraker API checks failed"
}

check_cfs() {
    section "CFS / BOX"
    echo "Safety: this check is read-only; it does not load, unload, extrude or move CFS filament."
    cfs_out=$(python3 - << 'PYEOF'
import json
import sys
import time
import urllib.request

url = "http://127.0.0.1:7125/printer/objects/query?box&motor_control&filament_switch_sensor%20filament_sensor&configfile"

last_error = ""
status = {}
attempt = 0
for attempt in range(1, 5):
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            status = json.loads(response.read().decode()).get("result", {}).get("status", {})
        box_probe = status.get("box", {})
        motor_probe = status.get("motor_control", {})
        if box_probe.get("state") == "connect" and motor_probe.get("motor_ready") is True:
            break
        last_error = "box=%s motor_ready=%s" % (box_probe.get("state"), motor_probe.get("motor_ready"))
    except Exception as exc:
        last_error = str(exc)
    if attempt < 4:
        time.sleep(2)
else:
    if not status:
        print("ERROR|%s" % last_error)
        sys.exit(1)

box = status.get("box", {})
motor = status.get("motor_control", {})
sensor = status.get("filament_switch_sensor filament_sensor", {})
configfile = status.get("configfile", {})
pending_items = configfile.get("save_config_pending_items", {}) or {}
pending_names = sorted(pending_items.keys())

print("CFS_CHECK_ATTEMPT|%s" % attempt)
if last_error:
    print("CFS_LAST_RECONNECT_STATE|%s" % last_error)
print("BOX_STATE|%s" % box.get("state"))
print("BOX_ENABLE|%s" % box.get("enable"))
print("BOX_AUTO_REFILL|%s" % box.get("auto_refill"))
print("BOX_FILAMENT_USEUP|%s" % box.get("filament_useup"))
t1 = box.get("T1", {})
print("T1_STATE|%s" % t1.get("state"))
print("T1_VERSION|%s" % t1.get("version"))
print("T1_SN|%s" % t1.get("sn"))
print("T1_REMAIN|%s" % ",".join(map(str, t1.get("remain_len", []))))
print("T1_MATERIAL|%s" % ",".join(map(str, t1.get("material_type", []))))
print("MOTOR_READY|%s" % motor.get("motor_ready"))
print("FILAMENT_SENSOR_ENABLED|%s" % sensor.get("enabled"))
print("FILAMENT_DETECTED|%s" % sensor.get("filament_detected"))
print("SAVE_CONFIG_PENDING|%s" % configfile.get("save_config_pending"))
print("SAVE_CONFIG_PENDING_ITEMS|%s" % ",".join(pending_names))
print("AUTO_ADDR_ONLY_PENDING|%s" % (pending_names == ["auto_addr"]))

failed = 0
if box.get("state") != "connect":
    failed = 1
if motor.get("motor_ready") is not True:
    failed = 1
sys.exit(failed)
PYEOF
)
    rc=$?
    echo "$cfs_out"
    [ "$rc" -eq 0 ] && ok "CFS/BOX and motor_control are connected" || fail "CFS/BOX or motor_control check failed"
    t1_version=$(printf "%s\n" "$cfs_out" | sed -n 's/^T1_VERSION|//p' | head -1)
    if [ "$t1_version" = "1.4.2" ]; then
        ok "CFS/T1 firmware matches 2026-07-07 handover baseline: 1.4.2"
    elif [ -n "$t1_version" ] && [ "$t1_version" != "None" ]; then
        info "CFS/T1 firmware is $t1_version; review release notes before CFS/firmware changes"
    else
        warn "CFS/T1 firmware version not available in Moonraker box status"
    fi
    if echo "$cfs_out" | grep -q "AUTO_ADDR_ONLY_PENDING|True"; then
        ok "Only auto_addr is pending; expected Creality CFS state, do not SAVE_CONFIG just for this"
    fi

    if [ -f "$CONFIG_DIR/box.cfg" ]; then
        if grep -q "BOX_EXTRUDE_MATERIAL" "$CONFIG_DIR/box.cfg" 2>/dev/null && \
           grep -q "\[gcode_macro BOX_LOAD_MATERIAL\]" "$CONFIG_DIR/box.cfg" 2>/dev/null; then
            ok "Direct BOX/CFS macro hazards are known; helper avoids direct load/refresh tests"
        else
            ok "No direct BOX load/refresh hazard detected in box.cfg"
        fi

        if grep -q "\[gcode_macro M8200\]" "$CONFIG_DIR/box.cfg" 2>/dev/null; then
            ok "Creality M8200/CR_BOX_* material-change path exists"
        else
            warn "Creality M8200/CR_BOX_* path not found in box.cfg"
        fi
    else
        fail "box.cfg not found"
    fi

    echo ""
    echo "CFS command/log safety scan summary:"
    if [ -f "$SCRIPT_DIR/scripts/cfs_safety_scan.sh" ]; then
        scan_summary=$(sh "$SCRIPT_DIR/scripts/cfs_safety_scan.sh" --compact 2>/tmp/cfs_safety_scan.err | tail -1)
        echo "$scan_summary"
        config_direct_risk=$(echo "$scan_summary" | sed -n 's/.*config_direct_risk=\([0-9][0-9]*\).*/\1/p')
        gcode_direct_risk=$(echo "$scan_summary" | sed -n 's/.*gcode_direct_risk=\([0-9][0-9]*\).*/\1/p')
        config_official=$(echo "$scan_summary" | sed -n 's/.*config_official=\([0-9][0-9]*\).*/\1/p')
        gcode_official=$(echo "$scan_summary" | sed -n 's/.*gcode_official=\([0-9][0-9]*\).*/\1/p')
        # Backward compatibility with older cfs_safety_scan.sh summaries.
        old_config_risk=$(echo "$scan_summary" | sed -n 's/.*config_risk=\([0-9][0-9]*\).*/\1/p')
        old_gcode_risk=$(echo "$scan_summary" | sed -n 's/.*gcode_risk=\([0-9][0-9]*\).*/\1/p')
        log_severe_hits=$(echo "$scan_summary" | sed -n 's/.*log_severe_hits=\([0-9][0-9]*\).*/\1/p')
        log_timeout_hits=$(echo "$scan_summary" | sed -n 's/.*log_timeout_hits=\([0-9][0-9]*\).*/\1/p')
        log_noise_hits=$(echo "$scan_summary" | sed -n 's/.*log_noise_hits=\([0-9][0-9]*\).*/\1/p')
        gcode_scan_limited=$(echo "$scan_summary" | sed -n 's/.*gcode_scan_limited=\([^|]*\).*/\1/p')
        config_direct_risk=${config_direct_risk:-${old_config_risk:-0}}
        gcode_direct_risk=${gcode_direct_risk:-${old_gcode_risk:-0}}
        config_official=${config_official:-0}
        gcode_official=${gcode_official:-0}
        log_severe_hits=${log_severe_hits:-0}
        log_timeout_hits=${log_timeout_hits:-0}
        log_noise_hits=${log_noise_hits:-0}
        print_active=0
        if [ -f "$LOGS_DIR/klippy.log" ] && tail -n 120 "$LOGS_DIR/klippy.log" | grep -q "print_stats: printing"; then
            print_active=1
        fi
        [ "$config_direct_risk" -gt 0 ] && warn "Direct high-risk CFS commands found in custom config files: $config_direct_risk; run helper.sh --cfs-safety-scan" || ok "No direct high-risk CFS commands found in custom config files"
        [ "$gcode_direct_risk" -gt 0 ] && warn "Direct high-risk CFS commands found in G-code files: $gcode_direct_risk; review before printing" || ok "No direct high-risk CFS commands found in scanned G-code files"
        [ "$config_official" -gt 0 ] && ok "Official Creality/CFS workflow tokens found in custom configs: $config_official; OK only for stock/known workflow macros"
        [ "$gcode_official" -gt 0 ] && ok "Official Creality/CFS workflow tokens found in scanned G-code: $gcode_official; OK for slicer/display/Creality toolchange workflows"
        [ "$log_severe_hits" -gt 0 ] && warn "Recent severe CFS error log evidence found by safety scan: $log_severe_hits" || ok "No recent severe CFS error log evidence found by safety scan"
        [ "$log_timeout_hits" -gt 120 ] && warn "High CFS RS485 timeout evidence found by safety scan: $log_timeout_hits" || ok "CFS RS485 timeout level acceptable in compact scan: $log_timeout_hits"
        if [ "$log_noise_hits" -gt 120 ]; then
            if [ "$print_active" -eq 1 ] && [ "$log_severe_hits" -eq 0 ] && [ "$log_timeout_hits" -le 120 ]; then
                ok "CFS bus raw-frame/noise is high during active printing but has no severe paired errors: $log_noise_hits"
            else
                warn "High CFS bus raw-frame/noise evidence found by safety scan: $log_noise_hits"
            fi
        else
            ok "CFS bus raw-frame/noise level acceptable in compact scan: $log_noise_hits"
        fi
        [ "$gcode_scan_limited" = "True" ] && warn "G-code safety scan was limited to newest files; run helper.sh --cfs-safety-scan for details"
    else
        warn "cfs_safety_scan.sh not found"
    fi

    if [ -f "$SCRIPT_DIR/scripts/cfs_protocol_report.sh" ]; then
        cfs_protocol_out=$(sh "$SCRIPT_DIR/scripts/cfs_protocol_report.sh" --compact 2>/tmp/cfs_protocol_report.err)
        cfs_protocol_rc=$?
        echo "$cfs_protocol_out"
        if [ "$cfs_protocol_rc" -eq 0 ]; then
            proto_field() {
                printf "%s\n" "$cfs_protocol_out" | tr '|' '\n' | awk -F= -v key="$1" '$1 == key {print $2; exit}'
            }
            proto_db_missing="$(proto_field db_missing)"
            proto_blank_labels="$(proto_field blank_live_labels)"
            proto_db_ambiguous="$(proto_field db_ambiguous)"
            proto_m8200="$(proto_field official_m8200)"
            proto_start_end="$(proto_field stock_start_end)"
            proto_db_missing="${proto_db_missing:-0}"
            proto_blank_labels="${proto_blank_labels:-0}"
            proto_db_ambiguous="${proto_db_ambiguous:-0}"
            [ "$proto_m8200" = "True" ] && ok "CFS protocol report confirms official M8200/CR_BOX path" || warn "CFS protocol report did not confirm official M8200/CR_BOX path"
            [ "$proto_start_end" = "True" ] && ok "CFS protocol report confirms stock START/END CFS hooks" || fail "CFS stock START/END CFS hooks missing"
            [ "$proto_db_missing" -gt 0 ] && warn "CFS protocol report found live material IDs missing from DB: $proto_db_missing" || ok "CFS protocol report found no missing live material DB IDs"
            [ "$proto_blank_labels" -gt 0 ] && ok "CFS protocol report notes DB-backed blank live labels: $proto_blank_labels" || ok "CFS protocol report live slot labels are filled"
            [ "$proto_db_ambiguous" -gt 0 ] && ok "CFS protocol report notes shared/ambiguous generic DB IDs: $proto_db_ambiguous" || ok "CFS protocol report found no ambiguous DB IDs"
        else
            err_line="$(cat /tmp/cfs_protocol_report.err 2>/dev/null | tail -1)"
            if [ -n "$err_line" ]; then
                warn "CFS protocol report failed or partial: $err_line"
            else
                warn "CFS protocol report is partial/unavailable; see CFS_PROTOCOL_STATUS_ERROR above"
            fi
        fi
    else
        warn "cfs_protocol_report.sh not found"
    fi

    echo ""
    echo "CFS material database integrity:"
    cfs_db_out=$(python3 - << 'PYEOF'
import json
import pathlib
import sys
import urllib.request

box_dir = pathlib.Path("/mnt/UDISK/creality/userdata/box")
required_json = [
    "material_database.json",
    "material_box_info.json",
    "material_modify_info.json",
    "tn_data.json",
    "usrMaterial/userMaterial.json",
]
optional_json = ["material_option.json"]
failed = 0
warned = 0

def load_json(rel, required=True):
    global failed, warned
    path = box_dir / rel
    if not path.exists():
        print(("DB_MISSING_REQUIRED|%s" if required else "DB_MISSING_OPTIONAL|%s") % rel)
        if required:
            failed = 1
        else:
            warned = 1
        return None
    try:
        data = json.loads(path.read_text(errors="replace"))
    except Exception as exc:
        print("DB_JSON_ERROR|%s|%s" % (rel, exc))
        failed = 1
        return None
    print("DB_JSON_OK|%s|%s" % (rel, path.stat().st_size))
    return data

db = load_json("material_database.json")
for rel in required_json[1:]:
    load_json(rel)
for rel in optional_json:
    load_json(rel, required=False)

profile_ids = set()
profile_names = {}
if db:
    for item in db.get("result", {}).get("list", []):
        base = item.get("base", {}) or {}
        base_id = str(base.get("id", ""))
        if not base_id:
            continue
        profile_ids.add(base_id)
        profile_ids.add(base_id.zfill(6))
        profile_names[base_id] = "%s/%s" % (base.get("brand", ""), base.get("name", ""))
    print("DB_PROFILE_COUNT|%s" % db.get("result", {}).get("count"))

try:
    with urllib.request.urlopen("http://127.0.0.1:7125/printer/objects/query?box", timeout=5) as response:
        status = json.loads(response.read().decode()).get("result", {}).get("status", {})
    t1 = status.get("box", {}).get("T1", {}) or {}
    live_ids = [str(v) for v in t1.get("material_type", []) if str(v) and str(v) not in ("-1", "None", "none", "null")]
except Exception as exc:
    print("DB_LIVE_BOX_ERROR|%s" % exc)
    live_ids = []
    warned = 1

missing = []
for live_id in live_ids:
    plain = live_id.lstrip("0") or live_id
    # Creality RFID-backed profiles may report one vendor digit before the
    # five-digit material profile id, e.g. live 101001 -> DB profile 01001.
    candidates = {live_id, live_id.zfill(6), plain, plain.zfill(5)}
    if len(live_id) == 6:
        candidates.add(live_id[1:])
    if not (candidates & profile_ids):
        missing.append(live_id)

if missing:
    print("DB_LIVE_ID_MISSING|%s" % ",".join(missing))
    warned = 1
else:
    print("DB_LIVE_ID_MATCH|%s" % ",".join(live_ids))

custom_expected = {
    "90001": "eSUN/ePLA-HS+ Gray",
    "90002": "Sovol/PLA Steel Blue",
}
for base_id, label in custom_expected.items():
    if base_id in profile_ids or base_id.zfill(6) in profile_ids:
        print("DB_CUSTOM_PROFILE_OK|%s|%s" % (base_id, profile_names.get(base_id, label)))
    elif base_id.zfill(6) in live_ids or base_id in live_ids:
        print("DB_CUSTOM_PROFILE_MISSING|%s|%s" % (base_id, label))
        warned = 1

if failed:
    sys.exit(2)
if warned:
    sys.exit(1)
PYEOF
)
    cfs_db_rc=$?
    echo "$cfs_db_out"
    if [ "$cfs_db_rc" -eq 0 ]; then
        ok "CFS material database matches live CFS slots"
    elif [ "$cfs_db_rc" -eq 1 ]; then
        warn "CFS material database has repairable inconsistencies; review DB_* lines above"
    else
        fail "CFS material database has missing or invalid required JSON"
    fi

    if is_installed "cfs_db_guard"; then
        if [ -x /etc/rc.d/S98cfs_db_guard ] && [ -f "$SCRIPT_DIR/scripts/cfs_db_guard.py" ] && [ -d "$SCRIPT_DIR/files/cfs_db_patch" ]; then
            ok "CFS material DB guard is installed"
            PYTHONDONTWRITEBYTECODE=1 python3 -B "$SCRIPT_DIR/scripts/cfs_db_guard.py" --check >/tmp/cfs_db_guard_check.log 2>&1
            guard_rc=$?
            cat /tmp/cfs_db_guard_check.log 2>/dev/null | tail -8
            if [ "$guard_rc" -eq 0 ]; then
                ok "CFS material DB guard check passed"
            elif [ "$guard_rc" -eq 1 ]; then
                warn "CFS material DB guard found repairable drift; run helper.sh --cfs-db-repair"
            else
                fail "CFS material DB guard check failed"
            fi
        else
            warn "cfs_db_guard is marked installed but service/script/patch snapshot is incomplete"
        fi
    elif [ -f "$SCRIPT_DIR/scripts/cfs_db_guard.py" ]; then
        warn "CFS material DB guard script exists but is not installed"
    fi

    if is_installed "cfs_safe_tools"; then
        safe_service=""
        [ -x /etc/init.d/S97cfs_safe_monitor ] && safe_service=/etc/init.d/S97cfs_safe_monitor
        [ -z "$safe_service" ] && [ -x /etc/rc.d/S97cfs_safe_monitor ] && safe_service=/etc/rc.d/S97cfs_safe_monitor
        if [ -x "$SCRIPT_DIR/scripts/cfs_safe_tools.py" ] && [ -n "$safe_service" ]; then
            ok "CFS Safe Tools is installed"
            safe_status="$($safe_service status 2>/dev/null || true)"
            echo "CFS_SAFE_SERVICE|$safe_status"
            safe_processes="$(proc_count_contains 'cfs_safe_tools.py --daemon')"
            if echo "$safe_status" | grep -q '^running:' && [ "$safe_processes" -eq 1 ]; then
                ok "CFS Safe Tools passive monitor has exactly one process"
            else
                warn "CFS Safe Tools monitor state is unexpected: service=${safe_status:-unknown}, processes=$safe_processes"
            fi
            PYTHONDONTWRITEBYTECODE=1 python3 -B "$SCRIPT_DIR/scripts/cfs_safe_tools.py" --status >/tmp/cfs_safe_tools_health.log 2>&1
            safe_rc=$?
            tail -12 /tmp/cfs_safe_tools_health.log 2>/dev/null
            safe_summary="$(sed -n 's/^SUMMARY|//p' /tmp/cfs_safe_tools_health.log | tail -1)"
            if [ "$safe_rc" -eq 0 ] && echo "$safe_summary" | grep -q 'WARN=0|FAIL=0'; then
                ok "CFS Safe Tools live summary has no warnings or failures"
            elif echo "$safe_summary" | grep -q 'FAIL=[1-9]'; then
                fail "CFS Safe Tools live summary reports a failure: ${safe_summary:-unavailable}"
            else
                warn "CFS Safe Tools live summary needs review: ${safe_summary:-unavailable}"
            fi
            if python3 - "$SCRIPT_DIR/state/cfs_safe_tools_state.json" << 'PYEOF'
import pathlib
import sys
import time
path = pathlib.Path(sys.argv[1])
sys.exit(0 if path.is_file() and time.time() - path.stat().st_mtime < 180 else 1)
PYEOF
            then
                ok "CFS Safe Tools state heartbeat is current"
            else
                warn "CFS Safe Tools state heartbeat is missing or older than 3 minutes"
            fi
        else
            fail "cfs_safe_tools is marked installed but worker/service is incomplete"
        fi
    elif [ -f "$SCRIPT_DIR/scripts/cfs_safe_tools.py" ]; then
        info "CFS Safe Tools worker is available but not installed"
    fi

    if [ -f "$LOGS_DIR/klippy.log" ]; then
        cfs_key60=$(tail -n 2000 "$LOGS_DIR/klippy.log" | grep -Ei "key60|Internal error|No active exception to reraise|BOX_INFO_REFRESH|BOX_SET_PRE_LOADING|BOX_LOAD_MATERIAL|BOX_EXTRUDE_MATERIAL|BOX_LOAD_MATERIAL_EXTRUDE_MATERIAL" | grep -Eiv "_handle_query|objects/query|configfile|gcode_macro|save_config_pending|^[[:space:]]*BOX_(INFO_REFRESH|SET_PRE_LOADING|EXTRUDE_MATERIAL|LOAD_MATERIAL_EXTRUDE_MATERIAL)\\b" | wc -l | awk '{print $1}')
        timeouts=$(tail -n 1000 "$LOGS_DIR/klippy.log" | grep -c "cmd_485_send_data_with_response timeout")
        buf_len=$(tail -n 1000 "$LOGS_DIR/klippy.log" | grep -c "buf_len = 0x")
        unknown=$(tail -n 1000 "$LOGS_DIR/klippy.log" | grep -Ec "Serial_485: got .*#unknown|#unknown")
        get_box_state=$(tail -n 500 "$LOGS_DIR/klippy.log" | grep -c "GET_BOX_STATE")
        ready_bug=$(tail -n 3000 "$LOGS_DIR/klippy.log" | grep -Ec "motor_control_wrapper\\.Motor_Control\\.set_motor_pin|No active exception to reraise|Internal error during ready callback")
        [ "$cfs_key60" -gt 0 ] && warn "Recent CFS direct macro/internal-error evidence in klippy.log: $cfs_key60" || ok "No recent CFS key60/direct macro evidence in last 2000 klippy lines"
        [ "$timeouts" -gt 120 ] && warn "High RS485 timeout noise in last 1000 klippy lines: $timeouts" || ok "RS485 timeout noise acceptable in last 1000 klippy lines: $timeouts"
        [ "$buf_len" -gt 10 ] && warn "High RS485 buf_len/noisy-frame evidence in last 1000 klippy lines: $buf_len" || ok "RS485 buf_len/noisy-frame level acceptable in last 1000 klippy lines: $buf_len"
        [ "$unknown" -gt 200 ] && warn "High Serial_485 unknown/noisy frames in last 1000 klippy lines: $unknown" || ok "Serial_485 unknown/noisy frame level acceptable in last 1000 klippy lines: $unknown"
        [ "$get_box_state" -gt 120 ] && warn "High GET_BOX_STATE polling lines in last 500 klippy lines: $get_box_state" || ok "GET_BOX_STATE polling level acceptable in last 500 klippy lines: $get_box_state"
        [ "$ready_bug" -gt 0 ] && warn "Recent Creality motor_control ready-callback bug evidence in klippy.log: $ready_bug" || ok "No recent motor_control ready-callback bug evidence"
    else
        warn "klippy.log not found"
    fi
}

check_logs_and_space() {
    section "Logs and space"
    df -h / /mnt/UDISK 2>/dev/null

    if [ -f "$LOGS_DIR/moonraker.log" ]; then
        helix_probe=$(tail -n 500 "$LOGS_DIR/moonraker.log" | grep -Ec "JSON-RPC Unknown Method: server\\.helix\\.status|JSON-RPC Request Error: -32601")
        moon_errors=$(tail -n 500 "$LOGS_DIR/moonraker.log" | grep -Ei "traceback|exception|error|failed" | grep -Eiv "startup_warnings: \\[\\]|Host repo mismatch|failed update|Missing release info|Unable to validate|Unable to find current release|Owner repo mismatch|Error closing Klippy Unix Socket|ConnectionResetError|Internal error during connect|Can not update MCU rpi config as it is shutdown|Printer is halted|Failed to build file list, invalid path: timelapse|Traceback \\(most recent call last\\)|/usr/share/moonraker/klippy_connection.py|/usr/lib/python3.9/asyncio|selector_events.py|^2020-01-01 .*CERTIFICATE_VERIFY_FAILED|^2020-01-01 .*certificate verify failed: certificate is not yet valid|^2020-01-01 .*Failed to update subscription '(moonraker|klipper)'|JSON-RPC Unknown Method: server\\.helix\\.status|JSON-RPC Request Error: -32601" | grep -Eiv "JSON-RPC Request Error: 400|utils\\.ServerError: No data for argument: value|raise ServerError\\(f\"No data for argument|^Traceback \\(most recent call last\\):?$" | wc -l | awk '{print $1}')
        [ "$helix_probe" -gt 0 ] && ok "HelixPrint optional-plugin probe is harmless in Moonraker log: $helix_probe"
        [ "$moon_errors" -eq 0 ] && ok "No important Moonraker errors in last 500 lines" || warn "Moonraker error-like lines in last 500 lines: $moon_errors"
    fi

    if [ -f "$LOGS_DIR/klippy.log" ]; then
        klip_errors=$(tail -n 500 "$LOGS_DIR/klippy.log" | grep -Ei "traceback|exception|shutdown|mcu.*shutdown|error" | grep -Eiv "buf_len = 0x|buf\\[[0-9]+\\] =|cmd_485|Serial_485|rfid\\[unknown\\] is error|webhooks: registering remote method 'shutdown_machine'|process_received .* Socket Closed|shutdown_value|shutdown_speed|max_error|ch_best_error|^[[:space:]]*BOX_(EXTRUDE_MATERIAL|LOAD_MATERIAL_EXTRUDE_MATERIAL)\\b" | wc -l | awk '{print $1}')
        buf_noise=$(tail -n 500 "$LOGS_DIR/klippy.log" | grep -c "buf_len = 0x")
        [ "$klip_errors" -eq 0 ] && ok "No important Klipper errors in last 500 lines" || warn "Klipper error-like lines in last 500 lines: $klip_errors"
        [ "$buf_noise" -gt 5 ] && warn "High buf_len noise in last 500 lines: $buf_noise" || ok "buf_len noise acceptable in last 500 lines: $buf_noise"
    fi
}

summary() {
    section "Summary"
    echo "OK: $OK_COUNT"
    echo "WARN: $WARN_COUNT"
    echo "FAIL: $FAIL_COUNT"
    [ "$FAIL_COUNT" -eq 0 ]
}

mode="${1:-all}"
case "$mode" in
    helper)
        check_helper_files
        check_timelapse_recover
        check_frontends
        check_spoolman_sync
        check_firmware
        check_moonraker
        check_logs_and_space
        ;;
    camera)
        check_camera
        ;;
    timelapse|timelapse-recover)
        check_timelapse_recover
        ;;
    cfs|box)
        check_cfs
        ;;
    cfs-safety|cfs_scan)
        sh "$SCRIPT_DIR/scripts/cfs_safety_scan.sh"
        ;;
    frontends|frontend|ui)
        check_frontends
        ;;
    spoolman|spoolman-cfs)
        check_spoolman_sync
        ;;
    firmware|system)
        check_firmware
        ;;
    all)
        check_helper_files
        check_camera
        check_timelapse_recover
        check_frontends
        check_spoolman_sync
        check_firmware
        check_moonraker
        check_cfs
        check_logs_and_space
        ;;
    *)
        echo "Usage: $0 {all|helper|camera|timelapse|cfs|cfs-safety|frontends|spoolman|firmware}"
        exit 2
        ;;
esac

summary
