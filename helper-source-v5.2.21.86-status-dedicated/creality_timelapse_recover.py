#!/usr/bin/env python3
"""Recover Creality K2 raw timelapse recordings into the stock delay_image list."""

import argparse
import gzip
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path


H264_PATH = Path("/mnt/UDISK/timelapse/main_output.h264")
DELAY_ROOT = Path("/mnt/UDISK/creality/userdata/delay_image")
VIDEO_DIR = DELAY_ROOT / "video"
COVER_DIR = DELAY_ROOT / "cover"
INFO_PATH = DELAY_ROOT / "delay_image_info.json"
PRINT_REFER_PATH = Path("/mnt/UDISK/creality/userdata/config/user_print_refer.json")
DISPLAY_LOG_DIR = Path("/mnt/UDISK/creality/userdata/log")
STATE_PATH = Path("/mnt/UDISK/helper-script/.creality_timelapse_recover_state.json")
MOONRAKER_URL = "http://127.0.0.1:7125/printer/objects/query?print_stats&virtual_sdcard&webhooks"


def log(message):
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {message}", flush=True)


def load_json(path, default):
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        return default
    except Exception as exc:
        log(f"WARN: could not read {path}: {exc}")
        return default


def write_json_atomic(path, data, backup=True):
    path.parent.mkdir(parents=True, exist_ok=True)
    if backup and path.exists():
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        shutil.copy2(path, f"{path}.bak.{stamp}")
    tmp = path.with_suffix(path.suffix + f".tmp.{os.getpid()}")
    with tmp.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    os.replace(tmp, path)


def delay_settings():
    data = load_json(PRINT_REFER_PATH, {})
    settings = data.get("delay_image", {}) if isinstance(data, dict) else {}
    return {
        "location": int(settings.get("location", 0) or 0),
        "interval": int(settings.get("interval", 1) or 1),
        "render": int(settings.get("frame", 15) or 15),
        "switch": int(settings.get("switch", 0) or 0),
    }


def moonraker_status():
    try:
        with urllib.request.urlopen(MOONRAKER_URL, timeout=3) as response:
            return json.load(response).get("result", {}).get("status", {})
    except Exception:
        return {}


def printer_busy(status):
    print_stats = status.get("print_stats", {})
    virtual_sdcard = status.get("virtual_sdcard", {})
    state = str(print_stats.get("state", "")).lower()
    return state in {"printing", "paused"} or bool(virtual_sdcard.get("is_active"))


def open_maybe_gzip(path):
    if path.suffix == ".gz":
        return gzip.open(path, "rt", encoding="utf-8", errors="ignore")
    return path.open("r", encoding="utf-8", errors="ignore")


def display_logs():
    current = DISPLAY_LOG_DIR / "display-server.log"
    paths = []
    if current.exists():
        paths.append(current)
    paths.extend(sorted(DISPLAY_LOG_DIR.glob("display-server.log.*.gz")))
    return paths


def parse_print_time(text):
    if not text:
        return 0
    total = 0
    match = re.search(r"(\d+)h", text)
    if match:
        total += int(match.group(1)) * 3600
    match = re.search(r"(\d+)m", text)
    if match:
        total += int(match.group(1)) * 60
    match = re.search(r"(\d+)s", text)
    if match:
        total += int(match.group(1))
    return total


def parse_display_metadata():
    starts = []
    start_re = re.compile(r"print work start id = (\d+), file name = (.+)")
    detail_re = re.compile(
        r"print work file size = (\d+), create time = (\d+), start time = (\d+),\s+total time = (\d+), consumables = ([^,]+), start way = (\d+)"
    )
    end_re = re.compile(r"end print, print_time:([0-9hms]+)")
    software_re = re.compile(r"software = ([A-Za-z0-9_ .-]+)")

    for path in display_logs():
        try:
            with open_maybe_gzip(path) as handle:
                for line in handle:
                    match = start_re.search(line)
                    if match:
                        starts.append(
                            {
                                "id": int(match.group(1)),
                                "name": match.group(2).strip(),
                                "printtime": 0,
                                "estimated_time": 0,
                                "software": "",
                            }
                        )
                        continue
                    if not starts:
                        continue
                    detail = detail_re.search(line)
                    if detail:
                        starts[-1]["estimated_time"] = int(detail.group(4))
                    end = end_re.search(line)
                    if end:
                        parsed = parse_print_time(end.group(1))
                        if parsed:
                            starts[-1]["printtime"] = parsed
                    software = software_re.search(line)
                    if software:
                        starts[-1]["software"] = software.group(1).strip()
        except Exception as exc:
            log(f"WARN: could not parse {path}: {exc}")
    return max(starts, key=lambda item: int(item.get("id", 0))) if starts else {}


def gcode_task_id(gcode_path):
    try:
        with Path(gcode_path).open("r", encoding="utf-8", errors="ignore") as handle:
            for _ in range(80):
                line = handle.readline()
                if not line:
                    break
                if line.startswith("; creality_task_id:"):
                    return line.split(":", 1)[1].strip()
                if line.startswith("; creality_uuid:"):
                    return line.split(":", 1)[1].strip()
    except Exception:
        pass
    return ""


def current_print_metadata(status):
    cur = status.get("virtual_sdcard", {}).get("cur_print_data", {})
    if not isinstance(cur, dict):
        return {}
    filename = cur.get("filename") or status.get("print_stats", {}).get("filename") or ""
    if not filename:
        return {}
    metadata = cur.get("metadata", {}) if isinstance(cur.get("metadata"), dict) else {}
    full_path = f"/mnt/UDISK/printer_data/gcodes/{filename}"
    return {
        "filename": filename,
        "name": full_path,
        "printtime": int(cur.get("print_duration") or cur.get("total_duration") or 0),
        "estimated_time": int(metadata.get("estimated_time") or 0),
        "start_time": int(cur.get("start_time") or 0),
        "end_time": int(cur.get("end_time") or 0),
        "printId": metadata.get("uuid") or gcode_task_id(full_path),
    }


def video_duration(path):
    proc = subprocess.run(
        ["ffmpeg", "-hide_banner", "-i", str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    match = re.search(r"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)", proc.stdout)
    if not match:
        return 0
    hours, minutes, seconds = match.groups()
    return max(1, int(round(int(hours) * 3600 + int(minutes) * 60 + float(seconds))))


def run_checked(args):
    proc = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stdout.strip() or f"{args[0]} failed with {proc.returncode}")
    if proc.stdout.strip():
        log(proc.stdout.strip().splitlines()[-1])


def convert_video(source, target, fps):
    tmp = target.with_name(f".{target.stem}.tmp{target.suffix}")
    if tmp.exists():
        tmp.unlink()
    args = [
        "ffmpeg",
        "-y",
        "-loglevel",
        "warning",
        "-framerate",
        str(fps),
        "-i",
        str(source),
        "-c:v",
        "copy",
        "-movflags",
        "+faststart",
        str(tmp),
    ]
    try:
        run_checked(args)
    except Exception as exc:
        log(f"WARN: stream-copy render failed, retrying with libx264: {exc}")
        run_checked(
            [
                "ffmpeg",
                "-y",
                "-loglevel",
                "warning",
                "-framerate",
                str(fps),
                "-i",
                str(source),
                "-c:v",
                "libx264",
                "-preset",
                "ultrafast",
                "-pix_fmt",
                "yuv420p",
                "-movflags",
                "+faststart",
                str(tmp),
            ]
        )
    os.replace(tmp, target)


def make_cover(video, cover):
    tmp = cover.with_name(f".{cover.stem}.tmp{cover.suffix}")
    if tmp.exists():
        tmp.unlink()
    try:
        run_checked(
            [
                "ffmpeg",
                "-y",
                "-loglevel",
                "warning",
                "-i",
                str(video),
                "-frames:v",
                "1",
                str(tmp),
            ]
        )
        os.replace(tmp, cover)
    except Exception as exc:
        log(f"WARN: could not create cover image: {exc}")
        current = Path("/tmp/creality/original/current_print_image.png")
        if current.exists():
            shutil.copy2(current, cover)


def source_key(path):
    stat = path.stat()
    return f"{stat.st_mtime_ns}:{stat.st_size}"


def listed_ids(info):
    return {int(item.get("id")) for item in info.get("list", []) if str(item.get("id", "")).isdigit()}


def metadata_matches_source(metadata, path, max_age_seconds=21600):
    """Reject stale display metadata from an older print for a newer raw capture."""
    if not isinstance(metadata, dict) or not metadata:
        return False
    try:
        candidate = int(metadata.get("id") or metadata.get("start_time") or 0)
    except Exception:
        return False
    if candidate <= 0:
        return False
    return abs(int(path.stat().st_mtime) - candidate) <= max_age_seconds


def stable_source(path, wait_seconds=5):
    first = source_key(path)
    time.sleep(wait_seconds)
    return first == source_key(path)


def fallback_id(path):
    return int(path.stat().st_mtime)


def unique_fallback_id(path, existing_ids):
    candidate = fallback_id(path)
    while candidate in existing_ids:
        candidate += 1
    return candidate


def recover_once(force=False):
    settings = delay_settings()
    if not H264_PATH.exists() or H264_PATH.stat().st_size <= 0:
        return "no raw Creality timelapse file found"
    if settings["switch"] != 1:
        return "Creality delay_image switch is disabled; nothing rendered"

    status = moonraker_status()
    if printer_busy(status) and not force:
        return "printer is busy; render deferred"
    if not force and not stable_source(H264_PATH):
        return "raw timelapse file is still changing; render deferred"

    state = load_json(STATE_PATH, {})
    key = source_key(H264_PATH)
    info = load_json(INFO_PATH, {"list": []})
    if "list" not in info or not isinstance(info["list"], list):
        info = {"list": []}

    last_video = state.get("last_video")
    if state.get("last_source_key") == key and not force and last_video and Path(str(last_video)).exists():
        return "raw timelapse file was already processed"

    display = parse_display_metadata()
    if display and not metadata_matches_source(display, H264_PATH):
        log(
            "WARN: latest display timelapse metadata is stale for this raw capture; "
            f"using fallback id from {H264_PATH.name}"
        )
        display = {}
    moon = current_print_metadata(status)
    gcode_name = os.path.basename(display.get("name") or moon.get("filename") or "unknown.gcode")
    gcode_path = display.get("name") or moon.get("name") or f"/mnt/UDISK/printer_data/gcodes/{gcode_name}"
    print_id = display.get("id") or moon.get("start_time") or fallback_id(H264_PATH)
    ids = listed_ids(info)
    if int(print_id) in ids:
        if state.get("last_source_key") == key and int(state.get("last_id", -1)) == int(print_id):
            return "raw timelapse file was already processed"
        old_print_id = int(print_id)
        print_id = unique_fallback_id(H264_PATH, ids)
        log(
            f"WARN: timelapse id {old_print_id} is already listed for another capture; "
            f"using recovered id {print_id}"
        )

    VIDEO_DIR.mkdir(parents=True, exist_ok=True)
    COVER_DIR.mkdir(parents=True, exist_ok=True)
    video = VIDEO_DIR / f"{print_id}.mp4"
    cover = COVER_DIR / f"{print_id}.png"
    fps = settings["render"] or 15

    log(f"rendering {H264_PATH} -> {video}")
    convert_video(H264_PATH, video, fps)
    make_cover(video, cover)

    duration = video_duration(video)
    printtime = int(
        display.get("printtime")
        or moon.get("printtime")
        or display.get("estimated_time")
        or moon.get("estimated_time")
        or 0
    )
    task_id = moon.get("printId") or gcode_task_id(gcode_path)
    if not task_id:
        task_id = hashlib.sha1(f"{print_id}:{gcode_name}".encode()).hexdigest()[:24]

    entry = {
        "dateTime": datetime.fromtimestamp(int(print_id)).strftime("%Y-%m-%d %H:%M:%S"),
        "name": gcode_path,
        "id": int(print_id),
        "video": str(video),
        "size": int(video.stat().st_size),
        "duration": int(duration),
        "cover": str(cover),
        "starttime": int(print_id),
        "printtime": int(printtime),
        "location": settings["location"],
        "interval": settings["interval"],
        "render": settings["render"],
        "videoid": str(print_id),
        "upload": 0,
        "gcodename": gcode_name,
        "videoname": video.name,
        "printId": task_id,
    }
    info["list"].append(entry)
    info["list"].sort(key=lambda item: int(item.get("id", 0)))
    write_json_atomic(INFO_PATH, info, backup=True)
    state.update({"last_source_key": key, "last_video": str(video), "last_id": int(print_id)})
    write_json_atomic(STATE_PATH, state, backup=False)
    return f"rendered and listed {video}"


def status():
    settings = delay_settings()
    info = load_json(INFO_PATH, {"list": []})
    state = load_json(STATE_PATH, {})
    result = {
        "raw_exists": H264_PATH.exists(),
        "raw_size": H264_PATH.stat().st_size if H264_PATH.exists() else 0,
        "delay_image_switch": settings["switch"],
        "delay_image_count": len(info.get("list", [])) if isinstance(info, dict) else 0,
        "state": state,
    }
    print(json.dumps(result, indent=2))


def daemon_loop(interval):
    log("Creality timelapse recover daemon started")
    last_quiet_message = None
    while True:
        try:
            message = recover_once(force=False)
            quiet = (
                message.startswith("raw timelapse file was already processed")
                or message == "no raw Creality timelapse file found"
            )
            if quiet:
                if message != last_quiet_message:
                    log(message)
                last_quiet_message = message
            else:
                log(message)
                last_quiet_message = None
        except Exception as exc:
            log(f"ERROR: {exc}")
            last_quiet_message = None
        time.sleep(interval)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true", help="run one recovery check")
    parser.add_argument("--force", action="store_true", help="render even if already processed or not stable")
    parser.add_argument("--daemon", action="store_true", help="watch and recover after future prints")
    parser.add_argument("--status", action="store_true", help="show status")
    parser.add_argument("--interval", type=int, default=30)
    args = parser.parse_args()

    if args.status:
        status()
        return 0
    if args.daemon:
        daemon_loop(max(10, args.interval))
        return 0
    if args.once or args.force:
        print(recover_once(force=args.force))
        return 0
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
