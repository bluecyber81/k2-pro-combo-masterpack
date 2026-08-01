#!/usr/bin/env python3
import json
import os
import subprocess
import time
import urllib.request

STREAMS_URL = 'http://127.0.0.1:1984/api/streams'
RECONNECT_URL = 'http://127.0.0.1:1984/api/streams?src=k2camera'
FAIL_LIMIT = 3
CHECK_INTERVAL = 10
CAMERA_SERVICE = '/etc/init.d/S99camera'


def process_count(prefix):
    count = 0
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            with open(f'/proc/{name}/cmdline', 'rb') as handle:
                command = handle.read().replace(b'\0', b' ')
            if command.startswith(prefix):
                count += 1
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return count


def cam_app_running():
    return process_count(b'/usr/bin/cam_app ') == 1


def ensure_cam_app():
    result = subprocess.run(
        [CAMERA_SERVICE, 'ensure-producer'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=10,
        check=False,
    )
    return result.returncode == 0 and cam_app_running()


def reconnect():
    if not ensure_cam_app():
        print('Creality cam_app recovery failed', flush=True)
        return
    try:
        urllib.request.urlopen(RECONNECT_URL, timeout=5).read()
        print('Stream reconnect requested', flush=True)
    except Exception as exc:
        print('Reconnect error:', exc, flush=True)


def stream_config_ok():
    if not cam_app_running():
        return False, 'Creality cam_app producer missing'
    webrtc_count = process_count(b'/usr/bin/webrtc_local')
    if webrtc_count != 1:
        return False, f'Creality webrtc_local count is {webrtc_count}'
    with urllib.request.urlopen(STREAMS_URL, timeout=3) as response:
        data = json.loads(response.read())
    stream = data.get('k2camera', {}) or {}
    producers = stream.get('producers') or []
    if not producers:
        return False, 'k2camera producer missing'
    return True, ''


print('Camera watchdog started in idle-safe stream mode', flush=True)
fail_count = 0

while True:
    try:
        ok, reason = stream_config_ok()
        if ok:
            if fail_count:
                print('Stream config recovered', flush=True)
            fail_count = 0
        else:
            fail_count += 1
            print('Watchdog stream config failed:', reason, flush=True)
            if reason.startswith('Creality ') and ensure_cam_app():
                print('Creality camera process state recovered', flush=True)
                fail_count = 0
    except Exception as exc:
        fail_count += 1
        print('Watchdog probe error:', exc, flush=True)

    if fail_count >= FAIL_LIMIT:
        print('Stream config unhealthy - reconnecting...', flush=True)
        reconnect()
        fail_count = 0

    time.sleep(CHECK_INTERVAL)
