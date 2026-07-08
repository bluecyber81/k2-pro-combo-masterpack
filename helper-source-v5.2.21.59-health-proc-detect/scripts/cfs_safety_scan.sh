#!/bin/sh
# cfs_safety_scan.sh - read-only CFS command and log safety scanner

SCRIPT_DIR=/mnt/UDISK/helper-script
CONFIG_DIR=/mnt/UDISK/printer_data/config
GCODE_DIR=/mnt/UDISK/printer_data/gcodes
LOGS_DIR=/mnt/UDISK/printer_data/logs

MODE="${1:-scan}"
MAX_HITS="${CFS_SCAN_MAX_HITS:-80}"

case "$MODE" in
    --compact|compact|summary)
        ;;
    *)
        echo "== CFS command/log safety scan =="
        echo "Safety: read-only only. This does not load, unload, extrude, cut, move filament, or send BOX_SEND_DATA."
        echo "Policy: direct BOX_* load/extrude/raw-bus commands are hazards; stock M8200/CR_BOX_* workflow tokens are reported separately as official workflow evidence."
        ;;
esac

python3 - "$MODE" "$CONFIG_DIR" "$GCODE_DIR" "$LOGS_DIR" "$MAX_HITS" << 'PYEOF'
import gzip
import os
import re
import sys
from pathlib import Path

mode = sys.argv[1]
config_dir = Path(sys.argv[2])
gcode_dir = Path(sys.argv[3])
logs_dir = Path(sys.argv[4])
max_hits = int(sys.argv[5])
compact_mode = mode in ("--compact", "compact", "summary")
verbose_mode = mode in ("--verbose", "verbose", "details", "full")
gcode_file_limit = int(os.environ.get(
    "CFS_SCAN_MAX_GCODE_FILES",
    "40" if compact_mode else "120",
))
gcode_char_limit = int(os.environ.get(
    "CFS_SCAN_MAX_GCODE_CHARS",
    "1200000" if compact_mode else "5000000",
))
log_tail_bytes = int(os.environ.get(
    "CFS_SCAN_LOG_TAIL_BYTES",
    "262144" if compact_mode else "524288",
))

# Commands below are unsafe as generic tests on this K2 Pro Combo because they
# can move/cut/extrude material, poke the RS485 bus directly, or trigger known
# key60/internal-error paths when used outside Creality's own state machine.
hazard_tokens = [
    "BOX_SEND_DATA",
    "BOX_LOAD_MATERIAL",
    "BOX_INFO_REFRESH",
    "BOX_SET_PRE_LOADING",
    "BOX_EXTRUDE_MATERIAL",
    "BOX_RETRUDE_MATERIAL",
    "BOX_EXTRUDER_EXTRUDE",
    "_CFS_LOAD",
    "_CFS_UNLOAD",
]

# These are stock Creality/CFS workflow tokens. They are not counted as direct
# risk by themselves, because display, slicer toolchange and stock M8200 paths
# are the preferred material workflow on this printer. They are still surfaced
# as INFO so hand-written G-code/configs can be reviewed when needed.
official_workflow_tokens = [
    "M8200",
    "CR_BOX_PRE_OPT",
    "CR_BOX_CUT",
    "CR_BOX_RETRUDE",
    "CR_BOX_EXTRUDE",
    "CR_BOX_WASTE",
    "CR_BOX_FLUSH",
    "CR_BOX_END_OPT",
]

tokens = hazard_tokens + official_workflow_tokens

token_re = re.compile(
    r"(?<![A-Za-z0-9_])(" + "|".join(re.escape(token) for token in tokens) + r")(?![A-Za-z0-9_])"
)
log_severe_re = re.compile(
    r"key(60|831|83[4-9]|84[0-9]|85[0-9]|86[0-5]|890)"
    r"|BOX_SEND_DATA|BOX_INFO_REFRESH|BOX_SET_PRE_LOADING|BOX_LOAD_MATERIAL|BOX_EXTRUDE_MATERIAL|BOX_RETRUDE_MATERIAL|BOX_EXTRUDER_EXTRUDE|_CFS_LOAD|_CFS_UNLOAD"
    r"|Internal error on command:BOX"
    r"|No active exception to reraise",
    re.IGNORECASE,
)
log_timeout_re = re.compile(r"cmd_485_send_data_with_response timeout", re.IGNORECASE)
log_noise_re = re.compile(
    r"Serial_485.*#unknown"
    r"|buf_len = 0x",
    re.IGNORECASE,
)
ignore_log_re = re.compile(
    r"_handle_query|objects/query|save_config_pending|gcode_macro|^Stats "
    r"|^\s*BOX_(EXTRUDE_MATERIAL|LOAD_MATERIAL)\b",
    re.IGNORECASE,
)


def rel(path, base):
    try:
        return str(path.relative_to(base))
    except Exception:
        return str(path)


def stripped_code(line):
    text = line.strip()
    if not text:
        return ""
    if text.startswith("#") or text.startswith(";"):
        return ""
    return text


def classify(token):
    return "HIGH" if token in hazard_tokens else "OFFICIAL"


def scan_text_file(path, base, source):
    hits = []
    try:
        with path.open("r", encoding="utf-8", errors="ignore") as handle:
            for lineno, line in enumerate(handle, 1):
                text = stripped_code(line)
                if not text:
                    continue
                match = token_re.search(text)
                if not match:
                    continue
                token = match.group(1)
                hits.append((source, rel(path, base), lineno, token, classify(token), text[:180]))
                if len(hits) >= max_hits:
                    break
    except Exception as exc:
        hits.append((source, rel(path, base), 0, "SCAN_ERROR", "WARN", str(exc)))
    return hits


def scan_gcode_file(path, base):
    hits = []
    read_chars = 0
    try:
        if str(path).lower().endswith(".gz"):
            handle = gzip.open(path, "rt", encoding="utf-8", errors="ignore")
        else:
            handle = path.open("r", encoding="utf-8", errors="ignore")
        with handle:
            for lineno, line in enumerate(handle, 1):
                read_chars += len(line)
                if read_chars > gcode_char_limit:
                    break
                text = stripped_code(line)
                if not text:
                    continue
                match = token_re.search(text)
                if not match:
                    continue
                token = match.group(1)
                hits.append(("gcode", rel(path, base), lineno, token, classify(token), text[:180]))
                if len(hits) >= max_hits:
                    break
    except Exception as exc:
        hits.append(("gcode", rel(path, base), 0, "SCAN_ERROR", "WARN", str(exc)))
    return hits


def tail_lines(path, byte_count=524288):
    try:
        with path.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            handle.seek(max(0, size - byte_count), os.SEEK_SET)
            data = handle.read().decode("utf-8", errors="ignore")
        return data.splitlines()
    except Exception:
        return []


def split_hits(hits):
    direct = [hit for hit in hits if hit[4] == "HIGH"]
    official = [hit for hit in hits if hit[4] == "OFFICIAL"]
    other = [hit for hit in hits if hit[4] not in ("HIGH", "OFFICIAL")]
    return direct, official, other


config_hits = []
official_box = False
direct_box_path = False
if config_dir.is_dir():
    for cfg in sorted(config_dir.rglob("*.cfg")):
        if cfg.name == "box.cfg":
            try:
                text = cfg.read_text(encoding="utf-8", errors="ignore")
                official_box = "[gcode_macro M8200]" in text
                direct_box_path = (
                    ("BOX_LOAD_MATERIAL" in text and "BOX_EXTRUDE_MATERIAL" in text)
                    or ("BOX_INFO_REFRESH" in text and "BOX_SET_PRE_LOADING" in text)
                )
            except Exception:
                official_box = False
            continue
        for hit in scan_text_file(cfg, config_dir, "config"):
            config_hits.append(hit)
            if len(config_hits) >= max_hits:
                break
        if len(config_hits) >= max_hits:
            break

gcode_hits = []
gcode_files_total = 0
gcode_files_scanned = 0
gcode_scan_limited = False
if gcode_dir.is_dir():
    gcode_files = [
        path for path in gcode_dir.rglob("*")
        if path.is_file() and str(path).lower().endswith((".gcode", ".gcode.gz"))
    ]
    gcode_files_total = len(gcode_files)
    gcode_files = sorted(gcode_files, key=lambda p: p.stat().st_mtime, reverse=True)
    if len(gcode_files) > gcode_file_limit:
        gcode_scan_limited = True
        gcode_files = gcode_files[:gcode_file_limit]
    for path in gcode_files:
        lower = str(path).lower()
        if not path.is_file() or not lower.endswith((".gcode", ".gcode.gz")):
            continue
        gcode_files_scanned += 1
        for hit in scan_gcode_file(path, gcode_dir):
            gcode_hits.append(hit)
            if len(gcode_hits) >= max_hits:
                break
        if len(gcode_hits) >= max_hits:
            break

config_direct_hits, config_official_hits, config_other_hits = split_hits(config_hits)
gcode_direct_hits, gcode_official_hits, gcode_other_hits = split_hits(gcode_hits)

log_severe_hits = []
log_timeout_hits = []
log_noise_hits = []
log_severe_count = 0
log_timeout_count = 0
log_noise_count = 0
klippy = logs_dir / "klippy.log"
for idx, line in enumerate(tail_lines(klippy, log_tail_bytes), 1):
    if ignore_log_re.search(line):
        continue
    if log_severe_re.search(line):
        log_severe_count += 1
        if len(log_severe_hits) < max_hits:
            log_severe_hits.append(("log", "klippy.log", idx, "CFS_SEVERE", "WARN", line[:220]))
    elif log_timeout_re.search(line):
        log_timeout_count += 1
        if len(log_timeout_hits) < max_hits:
            log_timeout_hits.append(("log", "klippy.log", idx, "CFS_TIMEOUT", "INFO", line[:220]))
    elif log_noise_re.search(line):
        log_noise_count += 1
        if len(log_noise_hits) < max_hits:
            log_noise_hits.append(("log", "klippy.log", idx, "CFS_NOISE", "INFO", line[:220]))

summary = (
    "CFS_SCAN_SUMMARY|official_box=%s|direct_box_path=%s|"
    "config_risk=%d|gcode_risk=%d|config_direct_risk=%d|gcode_direct_risk=%d|"
    "config_official=%d|gcode_official=%d|config_hits=%d|gcode_hits=%d|"
    "gcode_files_scanned=%d|gcode_files_total=%d|gcode_scan_limited=%s|"
    "log_severe_hits=%d|log_timeout_hits=%d|log_error_hits=%d|log_noise_hits=%d|log_hits=%d"
    % (
        official_box,
        direct_box_path,
        len(config_direct_hits),
        len(gcode_direct_hits),
        len(config_direct_hits),
        len(gcode_direct_hits),
        len(config_official_hits),
        len(gcode_official_hits),
        len(config_hits),
        len(gcode_hits),
        gcode_files_scanned,
        gcode_files_total,
        gcode_scan_limited,
        log_severe_count,
        log_timeout_count,
        log_severe_count + log_timeout_count,
        log_noise_count,
        log_severe_count + log_timeout_count + log_noise_count,
    )
)

if compact_mode:
    print(summary)
    sys.exit(0)

print("CFS bus model: /dev/ttyS5, 230400 baud, serial_485 -> box_wrapper -> CFS address 0x01..0x04")
print("Known-safe policy: read status and logs; use display/slicer/stock M8200 workflow for material movement; avoid direct BOX_* tests.")
print(summary)
print("")

print("== Official box.cfg shape ==")
print("M8200/CR_BOX path present: %s" % official_box)
print("Direct BOX_LOAD_MATERIAL -> BOX_EXTRUDE_MATERIAL path present in stock box.cfg: %s" % direct_box_path)
if direct_box_path:
    print("Note: this is stock Creality logic, not itself a file error. The helper avoids triggering it directly.")
print("")


def print_hits(title, hits, normal_label):
    print("== %s ==" % title)
    if not hits:
        print("No %s found." % normal_label)
        print("")
        return
    show = hits if verbose_mode else hits[:max(5, min(max_hits, 20))]
    for source, file_name, lineno, token, severity, text in show:
        print("%s|%s|%s:%s|%s|%s" % (severity, token, file_name, lineno, source, text))
    if len(hits) > len(show):
        print("Showing %d of %d lines. Run with --verbose for more details." % (len(show), len(hits)))
    elif len(hits) >= max_hits:
        print("Output limited to %d hits." % max_hits)
    print("")


print_hits("Custom config direct CFS hazard scan", config_direct_hits + config_other_hits, "direct high-risk CFS command patterns")
print_hits("Custom config official CFS workflow token scan", config_official_hits, "official CFS workflow tokens outside stock box.cfg")
print_hits("G-code direct CFS hazard scan", gcode_direct_hits + gcode_other_hits, "direct high-risk CFS command patterns")
print_hits("G-code official CFS workflow token scan", gcode_official_hits, "official CFS workflow tokens")
if gcode_scan_limited:
    print("G-code scan note: scanned newest %d of %d G-code files. Set CFS_SCAN_MAX_GCODE_FILES to scan more." % (
        gcode_files_scanned,
        gcode_files_total,
    ))
    print("")


def print_log_hits(title, hits, total_count, normal_label):
    print("== %s ==" % title)
    if not hits:
        print("No %s found." % normal_label)
        print("")
        return
    show_count = len(hits) if verbose_mode else min(len(hits), 5)
    for source, file_name, lineno, token, severity, text in hits[:show_count]:
        print("%s|%s|%s:%s|%s|%s" % (severity, token, file_name, lineno, source, text))
    if not verbose_mode and total_count > show_count:
        print("Showing %d of %d lines. Run with --verbose for full details." % (show_count, total_count))
    elif len(hits) >= max_hits:
        print("Output limited to %d hits." % max_hits)
    print("")


print_log_hits("Recent Klipper CFS severe error log scan", log_severe_hits, log_severe_count, "severe CFS error patterns")
print_log_hits("Recent Klipper CFS timeout log scan", log_timeout_hits, log_timeout_count, "CFS timeout patterns")
print_log_hits("Recent Klipper CFS bus noise log scan", log_noise_hits, log_noise_count, "CFS bus noise patterns")

print("Recommendation:")
if config_direct_hits or gcode_direct_hits or config_other_hits or gcode_other_hits:
    print("- Review the HIGH/WARN direct-risk lines before printing. Do not run custom CFS load/unload/raw-bus commands on this K2 Pro Combo.")
else:
    print("- No custom direct CFS command hazards were found in configs or scanned G-code files.")
if config_official_hits or gcode_official_hits:
    print("- Official M8200/CR_BOX workflow tokens were found. This is OK when produced by stock Creality/display/slicer workflows; review only if they are hand-written custom material movement commands.")
if log_severe_count:
    print("- Recent logs contain CFS/bus/error evidence; run the CFS/BOX diagnosis and use display/Creality workflow for material movement.")
else:
    print("- Recent logs do not show notable severe CFS error patterns in the scanned tail.")
if log_timeout_count:
    print("- RS485 timeout lines are present. Low counts can happen with Creality polling; high counts should be watched with health.sh cfs.")
if log_noise_count:
    print("- Bus raw-frame/noise lines are present. These are not automatically CFS failures unless paired with key/error/timeout entries.")

sys.exit(0)
PYEOF
