#!/bin/sh
# camera.sh - Install K2 Series camera support for Fluidd and Mainsail
# Credit: DnG-Crafts (https://github.com/DnG-Crafts/K2-Camera)
#         AlexxIT/go2rtc (https://github.com/AlexxIT/go2rtc)
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"
GO2RTC=$SCRIPT_DIR/go2rtc
GO2RTC_YAML=$SCRIPT_DIR/go2rtc.yaml
K2RTC=$SCRIPT_DIR/k2rtc.py
WATCHDOG=$SCRIPT_DIR/camera_watchdog.py

install_camera() {
    echo ""
    echo ""
    echo "======================================================"
    echo "  Camera Support for Fluidd and Mainsail"
    echo "======================================================"
    echo ""
    echo "  This installs a WebRTC bridge that makes the K2 Series"
    echo "  camera available in both Fluidd and Mainsail dashboards."
    echo ""
    echo "  Credit: DnG-Crafts and AlexxIT/go2rtc"
    echo ""

    echo ""
    printf "%b\n" "  ${YELLOW}NOTE: The camera bridge will be started immediately after install.${NC}"
    printf "  Continue? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }

    # Restore go2rtc from an older helper backup when available, otherwise download it.
    if [ ! -s "$GO2RTC" ]; then
        for candidate in $(ls -1t /mnt/UDISK/helper-script.bak.*/go2rtc 2>/dev/null); do
            if [ -s "$candidate" ]; then
                log_info "Restoring go2rtc from $candidate"
                cp "$candidate" "$GO2RTC"
                break
            fi
        done
    fi
    if [ ! -s "$GO2RTC" ]; then
        log_info "Downloading go2rtc (ARM)..."
        python3 -c "
import urllib.request
urllib.request.urlretrieve(
    'https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_arm',
    '$GO2RTC'
)
print('Downloaded go2rtc')
"
    fi
    if [ ! -s "$GO2RTC" ]; then
        log_error "go2rtc binary is still missing. Camera support cannot be installed."
        return 1
    fi
    chmod +x "$GO2RTC"

    # Get printer IP, with safe fallbacks if no default route is available yet.
    PRINTER_IP=$(python3 - << 'PYEOF'
import re
import subprocess

def run(cmd):
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode()
    except Exception:
        return ""

route = run(["ip", "route", "get", "1"])
m = re.search(r"\bsrc\s+([0-9.]+)", route)
if m:
    print(m.group(1))
    raise SystemExit

for part in run(["hostname", "-I"]).split():
    if re.match(r"^\d+\.\d+\.\d+\.\d+$", part):
        print(part)
        raise SystemExit

print("127.0.0.1")
PYEOF
)

    # Create go2rtc config
    cat > "$GO2RTC_YAML" << YAML
api:
  listen: :1984
  origin: '*'

rtsp:
  listen: :8554

streams:
  k2camera:
    - "webrtc:http://127.0.0.1:8000/call/webrtc_local#format=creality"

webrtc:
  listen: :8555
  candidates:
    - ${PRINTER_IP}:8555
  ice_servers:
    - urls:
        - stun:stun.l.google.com:19302
YAML

    # Create k2rtc.py bridge
    cat > $K2RTC << 'PYTHON'
#!/usr/bin/env python3
import http.server, urllib.request, json, base64, time

class K2Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        sdp = self.rfile.read(length).decode()
        offer = {'type': 'offer', 'sdp': sdp}
        payload = base64.b64encode(json.dumps(offer).encode())
        req = urllib.request.Request(
            'http://127.0.0.1:8000/call/webrtc_local',
            data=payload, method='POST',
            headers={'Content-Type': 'plain/text'}
        )
        try:
            r = urllib.request.urlopen(req, timeout=10)
            response = r.read()
            decoded = base64.b64decode(response)
            data = json.loads(decoded)
            answer_sdp = data['sdp'].encode()
            time.sleep(0.1)
            self.send_response(200)
            self.send_header('Content-Type', 'application/sdp')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Content-Length', len(answer_sdp))
            self.end_headers()
            self.wfile.write(answer_sdp)
            print('Bridge connected', flush=True)
        except Exception as e:
            print('Error:', e, flush=True)
            self.send_response(500)
            self.end_headers()
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.end_headers()

server = http.server.HTTPServer(('127.0.0.1', 8090), K2Handler)
print('K2 bridge running on 8090', flush=True)
server.serve_forever()
PYTHON

    # Create watchdog
    cat > $WATCHDOG << 'PYTHON'
#!/usr/bin/env python3
import urllib.request, json, time

STREAMS_URL = 'http://127.0.0.1:1984/api/streams'
RECONNECT_URL = 'http://127.0.0.1:1984/api/streams?src=k2camera'
FAIL_LIMIT = 3
CHECK_INTERVAL = 10

def reconnect():
    try:
        urllib.request.urlopen(RECONNECT_URL, timeout=10).read()
        print('Stream reconnected', flush=True)
    except Exception as e:
        print('Reconnect error:', e, flush=True)

def has_producer():
    with urllib.request.urlopen(STREAMS_URL, timeout=3) as response:
        data = json.loads(response.read())
    producers = data.get('k2camera', {}).get('producers', [])
    return bool(producers)

print('Camera watchdog started', flush=True)
fail_count = 0
last_error = ''
while True:
    try:
        if not has_producer():
            fail_count += 1
            last_error = 'no producer'
        else:
            if fail_count:
                print('Stream config recovered', flush=True)
            fail_count = 0
            last_error = ''

        if fail_count >= FAIL_LIMIT:
            print('Stream unhealthy (%s) - reconnecting...' % last_error, flush=True)
            reconnect()
            fail_count = 0
    except Exception as e:
        fail_count += 1
        last_error = str(e)
        print('Watchdog probe error:', e, flush=True)
        if fail_count >= FAIL_LIMIT:
            print('Stream unhealthy (%s) - reconnecting...' % last_error, flush=True)
            reconnect()
            fail_count = 0
    time.sleep(CHECK_INTERVAL)
PYTHON
    chmod +x "$K2RTC" "$WATCHDOG" 2>/dev/null

    # Create startup service
    cat > /etc/rc.d/S99camera << 'SHELL'
#!/bin/sh
HELIX=/mnt/UDISK/helper-script
RUN_DIR=/tmp/k2camera
K2RTC_PID=$RUN_DIR/k2rtc.pid
GO2RTC_PID=$RUN_DIR/go2rtc.pid
WATCHDOG_PID=$RUN_DIR/watchdog.pid
LOCK_DIR=$RUN_DIR/service.lock

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> /tmp/camera_startup.log
}

ensure_run_dir() {
    mkdir -p "$RUN_DIR"
}

acquire_lock() {
    ensure_run_dir
    i=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        lock_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
        if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
            rm -rf "$LOCK_DIR"
            continue
        fi
        i=$((i+1))
        if [ "$i" -ge 30 ]; then
            log_msg "Camera service lock busy"
            return 1
        fi
        sleep 1
    done
    echo "$$" > "$LOCK_DIR/pid"
    return 0
}

release_lock() {
    rm -rf "$LOCK_DIR"
}

run_locked() {
    acquire_lock || exit 1
    trap release_lock EXIT INT TERM
    "$@"
    rc=$?
    release_lock
    trap - EXIT INT TERM
    exit "$rc"
}

pid_alive() {
    pid="$1"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

stop_pid_file() {
    pid_file="$1"
    name="$2"
    if [ -f "$pid_file" ]; then
        pid="$(cat "$pid_file" 2>/dev/null)"
        if pid_alive "$pid"; then
            log_msg "Stopping $name pid $pid"
            kill "$pid" 2>/dev/null
            i=0
            while pid_alive "$pid" && [ "$i" -lt 10 ]; do
                sleep 1
                i=$((i+1))
            done
            if pid_alive "$pid"; then
                log_msg "Force stopping $name pid $pid"
                kill -9 "$pid" 2>/dev/null
            fi
        fi
        rm -f "$pid_file"
    fi
}

cmdline_for_pid() {
    tr '\000' ' ' < "/proc/$1/cmdline" 2>/dev/null
}

cmdline_matches_start() {
    cmd="$1"
    expected="$2"
    case "$cmd" in
        "$expected"|"$expected "*) return 0 ;;
        *) return 1 ;;
    esac
}

cmdline_contains() {
    cmd="$1"
    expected="$2"
    case "$cmd" in
        *"$expected"*) return 0 ;;
        *) return 1 ;;
    esac
}

kill_exact() {
    expected="$1"
    for proc in /proc/[0-9]*; do
        [ -r "$proc/cmdline" ] || continue
        pid="${proc##*/}"
        [ "$pid" = "$$" ] && continue
        cmd="$(cmdline_for_pid "$pid")"
        if cmdline_matches_start "$cmd" "$expected"; then
            kill "$pid" 2>/dev/null
        fi
    done
}

kill_contains() {
    expected="$1"
    for proc in /proc/[0-9]*; do
        [ -r "$proc/cmdline" ] || continue
        pid="${proc##*/}"
        [ "$pid" = "$$" ] && continue
        cmd="$(cmdline_for_pid "$pid")"
        if cmdline_contains "$cmd" "$expected"; then
            kill "$pid" 2>/dev/null
        fi
    done
}

count_exact() {
    expected="$1"
    count=0
    for proc in /proc/[0-9]*; do
        [ -r "$proc/cmdline" ] || continue
        cmd="$(cmdline_for_pid "${proc##*/}")"
        if cmdline_matches_start "$cmd" "$expected"; then
            count=$((count + 1))
        fi
    done
    echo "$count"
}

count_contains() {
    expected="$1"
    count=0
    for proc in /proc/[0-9]*; do
        [ -r "$proc/cmdline" ] || continue
        cmd="$(cmdline_for_pid "${proc##*/}")"
        if cmdline_contains "$cmd" "$expected"; then
            count=$((count + 1))
        fi
    done
    echo "$count"
}

stop() {
    ensure_run_dir
    stop_pid_file "$WATCHDOG_PID" "camera watchdog"
    stop_pid_file "$GO2RTC_PID" "go2rtc"
    stop_pid_file "$K2RTC_PID" "k2rtc"
    kill_contains "$HELIX/camera_watchdog.py"
    kill_contains "$HELIX/k2rtc.py"
    kill_exact "$HELIX/go2rtc"
    sleep 1
}

start() {
    ensure_run_dir
    delay="${CAMERA_START_DELAY:-0}"
    case "$delay" in
        ''|*[!0-9]*) delay=0 ;;
    esac
    [ "$delay" -gt 0 ] && sleep "$delay"
    stop
    if [ ! -x "$HELIX/go2rtc" ]; then
        log_msg "go2rtc missing or not executable"
        exit 1
    fi
    if [ ! -f "$HELIX/go2rtc.yaml" ]; then
        log_msg "go2rtc.yaml missing"
        exit 1
    fi
    log_msg "Starting K2 camera direct go2rtc"
    rm -f "$K2RTC_PID"
    "$HELIX/go2rtc" -config "$HELIX/go2rtc.yaml" >> /tmp/go2rtc.log 2>&1 &
    echo $! > "$GO2RTC_PID"
    log_msg "Camera direct go2rtc started"
    sleep 5
    PYTHONDONTWRITEBYTECODE=1 python3 -B "$HELIX/camera_watchdog.py" >> /tmp/watchdog.log 2>&1 &
    echo $! > "$WATCHDOG_PID"
}

boot() {
    CAMERA_START_DELAY="${CAMERA_START_DELAY:-60}" start
}

status() {
    netstat -lnt 2>/dev/null | grep -q ':1984 ' && echo "go2rtc API listening" || echo "go2rtc API not listening"
    echo "process counts: go2rtc=$(count_exact "$HELIX/go2rtc") k2rtc=$(count_contains "$HELIX/k2rtc.py") watchdog=$(count_contains "$HELIX/camera_watchdog.py")"
    ps | grep -E 'go2rtc|k2rtc.py|camera_watchdog.py' | grep -v grep
}

health() {
    status
    python3 - << 'PYEOF'
import sys
import urllib.request

checks = [
    ("streams", "http://127.0.0.1:1984/api/streams"),
]
failed = 0
for label, url in checks:
    try:
        with urllib.request.urlopen(url, timeout=8) as response:
            data = response.read(1024)
            ctype = response.headers.get("content-type", "")
            print("[OK] %s %s %s bytes_sample=%s" % (label, response.status, ctype, len(data)))
    except Exception as exc:
        failed += 1
        print("[FAIL] %s %s" % (label, exc))
sys.exit(1 if failed else 0)
PYEOF
}

case "$1" in
    start) run_locked start ;;
    boot) run_locked boot ;;
    stop) run_locked stop ;;
    restart) acquire_lock || exit 1; trap release_lock EXIT INT TERM; stop; sleep 1; start; rc=$?; release_lock; trap - EXIT INT TERM; exit "$rc" ;;
    status) status ;;
    health) health ;;
    *) echo "Usage: $0 {start|boot|stop|restart|status|health}" ;;
esac
SHELL
    chmod +x /etc/rc.d/S99camera
    cp /etc/rc.d/S99camera /etc/init.d/S99camera

    # v5.2.3 safety: back up files before touching rc.local, nginx, or dashboard HTML.
    backup_nginx_conf
    TS=$(date +%Y%m%d_%H%M%S)
    [ -f /etc/rc.local ] && cp -a /etc/rc.local "$SCRIPT_DIR/.rc.local.camera.bak.$TS" 2>/dev/null
    [ -f /usr/share/fluidd/index.html ] && cp -a /usr/share/fluidd/index.html "$SCRIPT_DIR/.fluidd_index.camera.bak.$TS" 2>/dev/null
    [ -f /usr/share/mainsail/index.html ] && cp -a /usr/share/mainsail/index.html "$SCRIPT_DIR/.mainsail_index.camera.bak.$TS" 2>/dev/null

    # Add to rc.local. Create a minimal rc.local if the firmware image does not provide one.
    python3 -c "
import os, re
path = '/etc/rc.local'
if os.path.exists(path):
    content = open(path).read()
else:
    content = '#!/bin/sh\nexit 0\n'
content = re.sub(r'\n?# K2 Camera bridge\n/etc/rc\.d/S99camera (?:start|boot) &\n', '\n', content)
if 'S99camera' not in content:
    if 'exit 0' in content:
        content = content.replace('exit 0', '# K2 Camera bridge\n/etc/rc.d/S99camera boot &\nexit 0', 1)
    else:
        content = content.rstrip() + '\n# K2 Camera bridge\n/etc/rc.d/S99camera boot &\nexit 0\n'
    open(path, 'w').write(content)
    print('Added to rc.local')
else:
    print('Already in rc.local')
"
    chmod +x /etc/rc.local 2>/dev/null || true

    # Add nginx proxy for go2rtc on port 4408 (Fluidd) and 4409 (Mainsail)
    python3 $SCRIPT_DIR/nginx_go2rtc.py || {
        log_error "Failed to update nginx for go2rtc. Camera install stopped before service start."
        return 1
    }

    # Add camera to Moonraker (one entry for both Fluidd and Mainsail)
    python3 -c "
import urllib.request, json, re, subprocess

def detect_ip():
    try:
        route = subprocess.check_output(['ip', 'route', 'get', '1'], stderr=subprocess.DEVNULL).decode()
        m = re.search(r'\bsrc\s+([0-9.]+)', route)
        if m:
            return m.group(1)
    except Exception:
        pass
    try:
        for part in subprocess.check_output(['hostname', '-I'], stderr=subprocess.DEVNULL).decode().split():
            if re.match(r'^\d+\.\d+\.\d+\.\d+$', part):
                return part
    except Exception:
        pass
    return '127.0.0.1'

ip = detect_ip()
for name in ['K2 Camera', 'K2 Camera Mainsail']:
    try:
        req = urllib.request.Request('http://127.0.0.1:7125/server/webcams/item?name=' + name.replace(' ', '%20'), method='DELETE')
        urllib.request.urlopen(req)
    except: pass

camera = {
    'name': 'K2 Camera',
    'enabled': True,
    'icon': 'mdiWebcam',
    'location': 'printer',
    'service': 'webrtc-go2rtc',
    'target_fps': 20,
    'target_fps_idle': 5,
    'stream_url': 'http://' + ip + ':1984/stream.html?src=k2camera&mode=webrtc',
    'snapshot_url': 'http://' + ip + ':1984/api/frame.jpeg?src=k2camera',
    'flip_horizontal': False,
    'flip_vertical': False,
    'rotation': 0,
    'aspect_ratio': '16:9',
    'extra_data': {}
}
data = json.dumps(camera).encode()
req = urllib.request.Request(
    'http://127.0.0.1:7125/server/webcams/item',
    data=data, method='POST',
    headers={'Content-Type': 'application/json'}
)
urllib.request.urlopen(req)
print('Camera added to Moonraker')
"

    # Creality's bundled Moonraker webcam component can predate the enabled
    # field required by Mainsail 2.18+. Add a tiny compatibility shim to the
    # API output so Mainsail does not hide an otherwise working camera.
    patch_out=$(python3 - << 'PYEOF'
from pathlib import Path
import shutil
import sys
import time

path = Path('/usr/share/moonraker/components/webcam.py')
marker = 'Mainsail 2.18+ hides webcam entries'
if not path.exists():
    print('MOONRAKER_WEBCAM_COMPAT_MISSING')
    sys.exit(0)

text = path.read_text()
if marker in text:
    print('MOONRAKER_WEBCAM_COMPAT_ALREADY')
    sys.exit(0)

old = '''    def as_dict(self):
        return {k: v for k, v in self.__dict__.items() if k[0] != "_"}
'''
new = '''    def as_dict(self):
        data = {k: v for k, v in self.__dict__.items() if k[0] != "_"}
        # Mainsail 2.18+ hides webcam entries unless Moonraker reports enabled=true.
        # Creality's bundled Moonraker webcam component predates that field.
        data.setdefault("enabled", True)
        data.setdefault("icon", "mdiWebcam")
        data.setdefault("target_fps_idle", self.target_fps)
        data.setdefault("aspect_ratio", "16:9")
        data.setdefault("extra_data", {})
        return data
'''
if old not in text:
    print('MOONRAKER_WEBCAM_COMPAT_UNEXPECTED')
    sys.exit(2)

backup = path.with_name(path.name + '.helper-before-mainsail-enabled-' + time.strftime('%Y%m%d_%H%M%S') + '.bak')
shutil.copy2(path, backup)
path.write_text(text.replace(old, new, 1))
print('MOONRAKER_WEBCAM_COMPAT_PATCHED|backup=%s' % backup)
PYEOF
    ) || {
        log_error "Moonraker webcam compatibility patch failed."
        return 1
    }
    echo "$patch_out"
    case "$patch_out" in
        *MOONRAKER_WEBCAM_COMPAT_PATCHED*)
            python3 - /usr/share/moonraker/components/webcam.py <<'PYEOF' || {
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
compile(path.read_text(), str(path), "exec")
PYEOF
                log_error "Patched Moonraker webcam.py does not compile."
                return 1
            }
            if command -v service >/dev/null 2>&1; then
                service moonraker restart
            else
                /etc/init.d/moonraker restart
            fi || {
                log_error "Moonraker restart failed after webcam compatibility patch."
                return 1
            }
            sleep 4
            ;;
    esac

    # Update Fluidd index.html with iframe keepalive and auto-reload
    python3 -c "
import os, re
path = '/usr/share/fluidd/index.html'
if not os.path.exists(path):
    print('Fluidd index.html not found; skipping Fluidd camera injection')
    raise SystemExit(0)
content = open(path).read()
content = re.sub(r'<iframe[^>]*go2rtc_keepalive[^>]*>.*?</iframe>', '', content)
content = re.sub(r'<script>\nvar cameraReady.*?</script>', '', content, flags=re.DOTALL)
script = '''<script>
var cameraReady = false;
function enableCamera() {
  try {
    var s = document.querySelector(\"#app\").__vue__.\$store;
    var cams = s.state.webcams.webcams;
    if(cams && cams.length > 0 && !cams[0].enabled) {
      cams[0].enabled = true;
      s.state.webcams.webcams.splice(0, 1, cams[0]);
    }
  } catch(e) {}
}
function checkAndReload() {
  fetch('/go2rtc/api/streams')
    .then(r => r.json())
    .then(data => {
      var stream = data.k2camera;
      var prod = stream && stream.producers && stream.producers[0];
      if(prod) {
        var cons = stream.consumers;
        var senderHasBytes = cons && cons.length > 0 && cons[0].senders &&
          cons[0].senders.some(function(s) { return s.bytes > 0; });
        if(senderHasBytes) {
          cameraReady = true;
          enableCamera();
        } else if(!cameraReady && prod.bytes_recv > 500000 && !sessionStorage.getItem(\'reloaded\')) {
          sessionStorage.setItem(\'reloaded\', \'1\');
          setTimeout(function() { location.reload(); }, 2000);
        }
      }
    })
    .catch(function() {});
}
setTimeout(enableCamera, 2000);
setInterval(checkAndReload, 3000);
</script>'''
content = content.replace('</body>', '<iframe src=\"/go2rtc/stream.html?src=k2camera&mode=webrtc\" style=\"display:none;width:1px;height:1px;\" id=\"go2rtc_keepalive\"></iframe>' + script + '</body>')
open(path, 'w').write(content)
print('Fluidd index.html updated')
"

    # Keep Mainsail clean. Mainsail 2.18+ reads the Moonraker webcam entry
    # directly; old Vue-store injection is brittle and can break after updates.
    python3 -c "
import re
import os
if not os.path.exists('/usr/share/mainsail/index.html'): exit(0)
content = open('/usr/share/mainsail/index.html').read()
content = re.sub(r'<iframe[^>]*go2rtc_keepalive[^>]*>.*?</iframe>', '', content)
content = re.sub(r'<script>.*?enableMainsailCams.*?</script>', '', content, flags=re.DOTALL)
open('/usr/share/mainsail/index.html', 'w').write(content)
print('Mainsail index.html kept clean; Moonraker webcam API is used')
"

    /etc/rc.d/S80nginx restart || {
        log_error "Nginx restart failed. Camera install stopped before service start."
        return 1
    }
    /etc/rc.d/S99camera restart || {
        log_error "Camera service failed to restart."
        return 1
    }
    sleep 3
    if netstat -lnt 2>/dev/null | grep -q ':1984 '; then
        log_success "go2rtc is listening on port 1984."
    else
        log_warn "go2rtc is not listening yet. Check /tmp/go2rtc.log and /tmp/k2rtc.log."
    fi
    mark_installed "camera_support"
    echo ""
    log_success "Camera support installed for Fluidd and Mainsail!"
    log_info "The camera service was started now; reboot is not required."
    log_info "After a later boot the camera can still take 60-90 seconds to appear."
}

remove_camera() {
    if ! is_installed "camera_support"; then
        if [ ! -e /etc/rc.d/S99camera ] && [ ! -e /etc/init.d/S99camera ]; then
            log_info "Camera Support is not installed."
            return 0
        fi
        log_warn "camera_support is not marked installed, but S99camera exists. Continuing cleanup."
    fi
    echo ""
    printf "%b\n" "${YELLOW}WARNING: This will remove the K2 camera support.${NC}"
    printf "Are you sure? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }

    # Stop services
    /etc/rc.d/S99camera stop 2>/dev/null

    # Remove startup entries
    rm -f /etc/rc.d/S99camera
    rm -f /etc/init.d/S99camera
    python3 -c "
import os, re
path = '/etc/rc.local'
if not os.path.exists(path):
    print('rc.local not found; nothing to remove')
    raise SystemExit(0)
content = open(path).read()
content = re.sub(r'\n?# K2 Camera bridge\n/etc/rc\.d/S99camera (?:start|boot) &\n', '\n', content)
open(path, 'w').write(content)
print('Removed from rc.local')
"

    # Remove nginx config
    python3 $SCRIPT_DIR/nginx_go2rtc.py remove || {
        log_error "Failed to remove nginx go2rtc proxy blocks."
        return 1
    }
    /etc/rc.d/S80nginx restart || {
        log_error "Nginx restart failed after removing camera proxy blocks."
        return 1
    }

    # Remove cameras from Moonraker
    python3 -c "
import urllib.request
for name in ['K2 Camera', 'K2 Camera Mainsail']:
    try:
        req = urllib.request.Request('http://127.0.0.1:7125/server/webcams/item?name=' + name.replace(' ', '%20'), method='DELETE')
        urllib.request.urlopen(req)
        print('Removed:', name)
    except: pass
"

    # Restore Fluidd index.html
    python3 -c "
import os, re
path = '/usr/share/fluidd/index.html'
if not os.path.exists(path):
    print('Fluidd index.html not found; nothing to restore')
    raise SystemExit(0)
content = open(path).read()
content = re.sub(r'<iframe[^>]*go2rtc_keepalive[^>]*></iframe>', '', content)
content = re.sub(r'<script>\nvar cameraReady.*?</script>', '', content, flags=re.DOTALL)
open(path, 'w').write(content)
print('Fluidd index.html restored')
"

    # Restore Mainsail index.html
    python3 -c "
import re
import os
if not os.path.exists('/usr/share/mainsail/index.html'): exit(0)
content = open('/usr/share/mainsail/index.html').read()
content = re.sub(r'<script>.*?enableMainsailCams.*?</script>', '', content, flags=re.DOTALL)
open('/usr/share/mainsail/index.html', 'w').write(content)
print('Mainsail index.html restored')
"

    mark_removed "camera_support"
    log_success "Camera support removed."
}

case "$1" in
    install) install_camera ;;
    remove)  remove_camera ;;
    *)       echo "Usage: $0 [install|remove]" ;;
esac
