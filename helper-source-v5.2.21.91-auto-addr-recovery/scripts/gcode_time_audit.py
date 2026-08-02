#!/usr/bin/env python3
"""Passively audit K2 Pro G-code remaining-time metadata.

The scanner reads files only. It never modifies G-code, calls Moonraker, sends
G-code, or controls the printer.
"""

import argparse
import json
import pathlib
import re
import sys


DEFAULT_GCODE_DIR = pathlib.Path("/mnt/UDISK/printer_data/gcodes")
TIME_RE = re.compile(
    r"^\s*;\s*estimated printing time \(normal mode\)\s*=\s*(.+?)\s*$",
    re.IGNORECASE,
)
M73_RE = re.compile(r"^\s*M73\b", re.IGNORECASE)
PROGRESS_RE = re.compile(r"(?:^|\s)P(?P<value>\d+(?:\.\d+)?)", re.IGNORECASE)
REMAINING_RE = re.compile(r"(?:^|\s)R(?P<value>\d+(?:\.\d+)?)", re.IGNORECASE)
TOOL_RE = re.compile(r"^\s*T(?P<tool>\d+)\s*(?:;.*)?$", re.IGNORECASE)
MARKER_RE = re.compile(r"K2PRO_HYBRID_TIME\s+v(?P<version>\d+)", re.IGNORECASE)
RELEVANT_BYTES_RE = re.compile(
    rb"^[ \t]*(?:"
    rb"M73\b[^\r\n]*|"
    rb"T\d+[ \t]*(?:;[^\r\n]*)?|"
    rb";[ \t]*(?:estimated printing time \(normal mode\)|K2PRO_HYBRID_TIME|"
    rb"Processed by klipper_estimator|post_process)[^\r\n]*"
    rb")",
    re.IGNORECASE | re.MULTILINE,
)


class AuditError(RuntimeError):
    """Raised for malformed inputs that cannot be audited safely."""


def time_to_seconds(value):
    matches = re.findall(r"(\d+)\s*([hms])", value.lower())
    if not matches:
        raise AuditError("unsupported estimated-time value: {}".format(value))
    factors = {"h": 3600, "m": 60, "s": 1}
    return sum(int(number) * factors[unit] for number, unit in matches)


def analyze_lines(lines, name="fixture.gcode"):
    estimates = []
    m73_values = []
    marker_version = None
    processed = False
    post_process_configured = False
    last_tool = None
    transitions = 0
    for line in lines:
        time_match = TIME_RE.match(line)
        if time_match:
            estimates.append(time_to_seconds(time_match.group(1)))
        if M73_RE.match(line):
            progress = PROGRESS_RE.search(line)
            remaining = REMAINING_RE.search(line)
            if progress and remaining:
                m73_values.append(
                    (float(progress.group("value")), float(remaining.group("value")))
                )
        tool_match = TOOL_RE.match(line)
        if tool_match:
            tool = int(tool_match.group("tool"))
            if last_tool is not None and tool != last_tool:
                transitions += 1
            last_tool = tool
        marker_match = MARKER_RE.search(line)
        if marker_match:
            marker_version = int(marker_match.group("version"))
        if "Processed by klipper_estimator" in line:
            processed = True
        if re.match(r"^\s*;\s*post_process\s*=\s*.+\S", line, re.IGNORECASE):
            post_process_configured = True

    estimate_seconds = estimates[-1] if estimates else None
    max_m73_minutes = max((remaining for _, remaining in m73_values), default=None)
    ratio = None
    if estimate_seconds and max_m73_minutes is not None:
        ratio = (max_m73_minutes * 60.0) / estimate_seconds

    findings = []
    if post_process_configured and not processed and marker_version is None:
        findings.append("configured_postprocessor_not_applied")
    if transitions > 0 and ratio is not None and ratio < 0.75:
        findings.append("cfs_remaining_time_omits_large_transition_share")
    if marker_version == 1 and transitions > 0:
        findings.append("legacy_v1_cfs_timeline")
    if not estimates:
        findings.append("estimated_time_comment_missing")
    if not m73_values:
        findings.append("m73_timeline_missing")

    warn_findings = {
        "configured_postprocessor_not_applied",
        "cfs_remaining_time_omits_large_transition_share",
        "estimated_time_comment_missing",
        "m73_timeline_missing",
    }
    level = "WARN" if any(item in warn_findings for item in findings) else "OK"
    return {
        "file": name,
        "level": level,
        "estimate_seconds": estimate_seconds,
        "m73_count": len(m73_values),
        "m73_max_minutes": max_m73_minutes,
        "m73_to_estimate_ratio": ratio,
        "tool_transitions": transitions,
        "hybrid_marker_version": marker_version,
        "processed_by_estimator": processed,
        "post_process_configured": post_process_configured,
        "findings": findings,
        "safety": "read_only_file_scan_no_printer_api_no_gcode_no_motion",
    }


def analyze_file(path):
    data = path.read_bytes()
    relevant = (
        match.group(0).decode("utf-8", errors="replace")
        for match in RELEVANT_BYTES_RE.finditer(data)
    )
    return analyze_lines(relevant, name=path.name)


def scan_directory(directory, max_files):
    if not directory.is_dir():
        raise AuditError("G-code directory is missing: {}".format(directory))
    files = sorted(
        (path for path in directory.iterdir() if path.is_file() and path.suffix.lower() == ".gcode"),
        key=lambda path: (path.stat().st_mtime, path.name.lower()),
        reverse=True,
    )[:max_files]
    return [analyze_file(path) for path in files]


def render(rows):
    warning_count = sum(row["level"] == "WARN" for row in rows)
    lines = [
        "GCODE_TIME_AUDIT_SUMMARY|files={}|warn={}|safety=read_only".format(
            len(rows), warning_count
        )
    ]
    for row in rows:
        ratio = row["m73_to_estimate_ratio"]
        lines.append(
            "GCODE_TIME_AUDIT|{}|file={}|estimate_s={}|m73_max_min={}|ratio={}|"
            "transitions={}|marker_v={}|findings={}".format(
                row["level"],
                row["file"],
                row["estimate_seconds"],
                row["m73_max_minutes"],
                "unknown" if ratio is None else "{:.3f}".format(ratio),
                row["tool_transitions"],
                row["hybrid_marker_version"],
                ",".join(row["findings"]) or "none",
            )
        )
    lines.append("GCODE_TIME_AUDIT_SAFETY|OK|read-only scan; no file or printer writes")
    return "\n".join(lines)


def selftest():
    rows = [
        "; estimated printing time (normal mode) = 1h\n",
        '; post_process = "K2Pro-CrealityPrint-Estimator.cmd"\n',
        "M73 P0 R20\n",
        "T0\n",
        "T1\n",
        "; K2PRO_HYBRID_TIME v1 strategy=creality-cfs base=3600 offset=60 target=3660 transitions=1 samples=9\n",
    ]
    report = analyze_lines(rows)
    if report["level"] != "WARN":
        raise AuditError("selftest did not flag the incomplete CFS timeline")
    if "cfs_remaining_time_omits_large_transition_share" not in report["findings"]:
        raise AuditError("selftest CFS finding is missing")
    print("SELFTEST|OK|passive G-code time audit")


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=pathlib.Path, default=DEFAULT_GCODE_DIR)
    parser.add_argument("--max-files", type=int, default=200)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    try:
        if args.selftest:
            selftest()
            return 0
        if args.max_files < 1 or args.max_files > 1000:
            raise AuditError("--max-files must be between 1 and 1000")
        rows = scan_directory(args.directory, args.max_files)
        if args.json:
            print(json.dumps(rows, ensure_ascii=True, indent=2, sort_keys=True))
        else:
            print(render(rows))
        return 1 if any(row["level"] == "WARN" for row in rows) else 0
    except (AuditError, OSError, ValueError) as exc:
        print("GCODE_TIME_AUDIT|FAIL|{}".format(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
