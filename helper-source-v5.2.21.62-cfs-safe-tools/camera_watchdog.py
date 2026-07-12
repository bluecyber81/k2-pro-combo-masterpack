#!/usr/bin/env python3
import json
import time
import urllib.request

STREAMS_URL = 'http://127.0.0.1:1984/api/streams'
RECONNECT_URL = 'http://127.0.0.1:1984/api/streams?src=k2camera'
FAIL_LIMIT = 3
CHECK_INTERVAL = 10


def reconnect():
    try:
        urllib.request.urlopen(RECONNECT_URL, timeout=5).read()
        print('Stream reconnect requested', flush=True)
    except Exception as exc:
        print('Reconnect error:', exc, flush=True)


def stream_config_ok():
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
    except Exception as exc:
        fail_count += 1
        print('Watchdog probe error:', exc, flush=True)

    if fail_count >= FAIL_LIMIT:
        print('Stream config unhealthy - reconnecting...', flush=True)
        reconnect()
        fail_count = 0

    time.sleep(CHECK_INTERVAL)
