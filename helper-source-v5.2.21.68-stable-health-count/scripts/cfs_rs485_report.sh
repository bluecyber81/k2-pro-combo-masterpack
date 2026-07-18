#!/bin/sh
# cfs_rs485_report.sh - read-only CFS RS485 log decoder for K2 Pro Combo

LOG_FILE=${1:-/mnt/UDISK/printer_data/logs/klippy.log}
MODE=${2:-summary}
TAIL_BYTES=${CFS_RS485_TAIL_BYTES:-524288}

echo "== CFS RS485 bus report =="
echo "Safety: read-only only. This does not send CFS/BOX commands."
echo "Log: $LOG_FILE"
echo ""

python3 - "$LOG_FILE" "$MODE" "$TAIL_BYTES" << 'PYEOF'
import json
import re
import sys
import urllib.request
from collections import Counter
from pathlib import Path

log_path = Path(sys.argv[1])
mode = sys.argv[2]
tail_bytes = int(sys.argv[3])
compact = mode in ("compact", "--compact", "summary")

function_names = {
    0x03: "remain_len/status",
    0x07: "slot/status short",
    0x0A: "temperature/humidity",
    0xA0: "set_slave_addr",
    0xA1: "get_slave_info",
    0xA2: "online_check",
    0xA3: "get_addr_table",
}

severe_re = re.compile(
    r"key(60|831|83[4-9]|84[0-9]|85[0-9]|86[0-5]|890)"
    r"|Internal error on command:BOX"
    r"|No active exception to reraise"
    r"|BOX_SEND_DATA|BOX_INFO_REFRESH|BOX_SET_PRE_LOADING"
    r"|BOX_LOAD_MATERIAL|BOX_EXTRUDE_MATERIAL|BOX_RETRUDE_MATERIAL|_CFS_LOAD|_CFS_UNLOAD",
    re.IGNORECASE,
)
timeout_re = re.compile(r"cmd_485_send_data_with_response timeout", re.IGNORECASE)
serial_re = re.compile(r"Serial_485: got .*?#msg': b'([^']+)'")
buf_re = re.compile(r"buf_len\s*=\s*0x", re.IGNORECASE)


def tail_text(path: Path, byte_count: int) -> str:
    try:
        with path.open("rb") as handle:
            handle.seek(0, 2)
            size = handle.tell()
            handle.seek(max(0, size - byte_count), 0)
            return handle.read().decode("utf-8", errors="ignore")
    except FileNotFoundError:
        return ""


def decode_bytes(escaped: str) -> bytes:
    try:
        return escaped.encode("utf-8").decode("unicode_escape").encode("latin1")
    except Exception:
        return b""


def moonraker_box_state() -> dict:
    url = "http://127.0.0.1:7125/printer/objects/query?box"
    try:
        with urllib.request.urlopen(url, timeout=3) as response:
            data = json.loads(response.read().decode("utf-8"))
        return data.get("result", {}).get("status", {}).get("box", {}) or {}
    except Exception as exc:
        return {"_error": str(exc)}


text = tail_text(log_path, tail_bytes)
lines = text.splitlines()
frame_count = 0
crc_shape_bad = 0
func_counts = Counter()
addr_counts = Counter()
examples = []

for line in lines:
    match = serial_re.search(line)
    if not match:
        continue
    frame = decode_bytes(match.group(1))
    if len(frame) < 6:
        crc_shape_bad += 1
        continue
    frame_count += 1
    if frame[0] != 0xF7:
        crc_shape_bad += 1
    addr_counts[frame[1]] += 1
    func_counts[frame[4]] += 1
    if len(examples) < 8:
        examples.append(" ".join("%02x" % b for b in frame[:24]))

timeouts = len(timeout_re.findall(text))
buf_noise = len(buf_re.findall(text))
severe_hits = [line for line in lines if severe_re.search(line)]
box = moonraker_box_state()
t1 = box.get("T1", {}) if isinstance(box, dict) else {}

print("BOX_STATE|%s" % box.get("state", "unknown"))
print("T1_STATE|%s" % (t1.get("state", "unknown") if isinstance(t1, dict) else "unknown"))
print("T1_VERSION|%s" % (t1.get("version", "unknown") if isinstance(t1, dict) else "unknown"))
print("T1_REMAIN|%s" % ",".join(t1.get("remain_len", []) if isinstance(t1, dict) else []))
print("T1_MATERIAL|%s" % ",".join(t1.get("material_type", []) if isinstance(t1, dict) else []))
print("RS485_SUMMARY|frames=%d|timeouts=%d|buf_len=%d|severe=%d|shape_bad=%d" % (
    frame_count,
    timeouts,
    buf_noise,
    len(severe_hits),
    crc_shape_bad,
))

print("")
print("Function counts:")
if func_counts:
    for func, count in sorted(func_counts.items(), key=lambda item: (-item[1], item[0])):
        print("  0x%02X %-24s %s" % (func, function_names.get(func, "unknown/creality"), count))
else:
    print("  none in selected log window")

print("")
print("Address counts:")
if addr_counts:
    for addr, count in sorted(addr_counts.items()):
        print("  0x%02X %s" % (addr, count))
else:
    print("  none")

if not compact:
    print("")
    print("Frame examples:")
    for example in examples:
        print("  %s" % example)
    if severe_hits:
        print("")
        print("Severe examples:")
        for line in severe_hits[-10:]:
            print("  %s" % line[-220:])

print("")
if len(severe_hits):
    print("[WARN] Severe CFS/BOX error evidence found in selected log window.")
elif box.get("state") == "connect" and isinstance(t1, dict) and t1.get("state") == "connect":
    print("[OK] CFS is connected; RS485 timeouts/noise are interpreted as background polling unless they rise sharply or CFS disconnects.")
else:
    print("[WARN] CFS connection state is not clean; check box/T1 state above.")

if timeouts > 80:
    print("[WARN] RS485 timeout count is elevated in this window: %d" % timeouts)
else:
    print("[OK] RS485 timeout count is acceptable in this window: %d" % timeouts)

if buf_noise > 3:
    print("[WARN] buf_len noise elevated in this window: %d" % buf_noise)
else:
    print("[OK] buf_len noise acceptable in this window: %d" % buf_noise)
PYEOF
