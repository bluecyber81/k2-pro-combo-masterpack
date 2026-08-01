#!/usr/bin/env python3
"""Strictly read-only diagnostics for the Creality K2 LAN WebSocket."""

import argparse
import base64
import hashlib
import json
import os
import secrets
import socket
import struct
import sys
import time


WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
SAFE_REQUESTS = (
    {"method": "get", "params": {"ReqPrinterPara": 1}},
    {"method": "get", "params": {"boxsInfo": 1}},
)
MATERIAL_REQUEST = {"method": "get", "params": {"reqMaterials": 1}}
FORBIDDEN_OUTPUT_KEYS = {
    "deviceId",
    "mac",
    "serial",
    "serialNumber",
    "token",
    "wifi",
}


class LanApiError(RuntimeError):
    """Raised when the read-only LAN query fails."""


def encode_client_frame(payload, opcode=0x1):
    if isinstance(payload, str):
        payload = payload.encode("utf-8")
    mask = secrets.token_bytes(4)
    length = len(payload)
    header = bytearray([0x80 | opcode])
    if length < 126:
        header.append(0x80 | length)
    elif length < 65536:
        header.append(0x80 | 126)
        header.extend(struct.pack("!H", length))
    else:
        header.append(0x80 | 127)
        header.extend(struct.pack("!Q", length))
    header.extend(mask)
    masked = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
    return bytes(header) + masked


def extract_frame(buffer):
    if len(buffer) < 2:
        return None, buffer
    first, second = buffer[0], buffer[1]
    final = bool(first & 0x80)
    opcode = first & 0x0F
    masked = bool(second & 0x80)
    length = second & 0x7F
    offset = 2
    if length == 126:
        if len(buffer) < 4:
            return None, buffer
        length = struct.unpack("!H", buffer[2:4])[0]
        offset = 4
    elif length == 127:
        if len(buffer) < 10:
            return None, buffer
        length = struct.unpack("!Q", buffer[2:10])[0]
        offset = 10
    mask = None
    if masked:
        if len(buffer) < offset + 4:
            return None, buffer
        mask = buffer[offset : offset + 4]
        offset += 4
    if len(buffer) < offset + length:
        return None, buffer
    payload = buffer[offset : offset + length]
    if mask:
        payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
    return (final, opcode, payload), buffer[offset + length :]


def read_http_headers(connection, timeout):
    connection.settimeout(timeout)
    response = bytearray()
    while b"\r\n\r\n" not in response:
        chunk = connection.recv(4096)
        if not chunk:
            raise LanApiError("WebSocket handshake closed early")
        response.extend(chunk)
        if len(response) > 65536:
            raise LanApiError("WebSocket handshake is too large")
    headers, remainder = bytes(response).split(b"\r\n\r\n", 1)
    lines = headers.decode("iso-8859-1").split("\r\n")
    if not lines or " 101 " not in " {} ".format(lines[0]):
        raise LanApiError("WebSocket handshake failed: {}".format(lines[0] if lines else "empty"))
    parsed = {}
    for line in lines[1:]:
        if ":" in line:
            name, value = line.split(":", 1)
            parsed[name.strip().lower()] = value.strip()
    return parsed, remainder


def merge_message(target, message):
    if not isinstance(message, dict):
        return
    for key, value in message.items():
        target[key] = value


def fetch_status(host, port, timeout, include_materials=False):
    requests = list(SAFE_REQUESTS)
    if include_materials:
        requests.append(MATERIAL_REQUEST)
    connection = socket.create_connection((host, port), timeout=timeout)
    try:
        key = base64.b64encode(secrets.token_bytes(16)).decode("ascii")
        handshake = (
            "GET / HTTP/1.1\r\n"
            "Host: {}:{}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            "Sec-WebSocket-Key: {}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "\r\n"
        ).format(host, port, key)
        connection.sendall(handshake.encode("ascii"))
        headers, buffer = read_http_headers(connection, timeout)
        expected_accept = base64.b64encode(
            hashlib.sha1((key + WEBSOCKET_GUID).encode("ascii")).digest()
        ).decode("ascii")
        if headers.get("sec-websocket-accept") != expected_accept:
            raise LanApiError("WebSocket server accept key is invalid")

        for request in requests:
            connection.sendall(
                encode_client_frame(json.dumps(request, separators=(",", ":")))
            )

        merged = {}
        fragmented_opcode = None
        fragmented_payload = bytearray()
        deadline = time.monotonic() + timeout
        connection.settimeout(min(timeout, 0.5))
        while time.monotonic() < deadline:
            frame, buffer = extract_frame(buffer)
            if frame is None:
                try:
                    chunk = connection.recv(65536)
                except socket.timeout:
                    continue
                if not chunk:
                    break
                buffer += chunk
                continue
            final, opcode, payload = frame
            text_payload = None
            if opcode == 0x1 and final:
                text_payload = payload
            elif opcode == 0x1:
                fragmented_opcode = opcode
                fragmented_payload = bytearray(payload)
            elif opcode == 0x0 and fragmented_opcode == 0x1:
                fragmented_payload.extend(payload)
                if final:
                    text_payload = bytes(fragmented_payload)
                    fragmented_opcode = None
                    fragmented_payload.clear()

            if text_payload is not None:
                try:
                    merge_message(merged, json.loads(text_payload.decode("utf-8")))
                except (UnicodeDecodeError, json.JSONDecodeError):
                    continue
            elif opcode == 0x8:
                break
            elif opcode == 0x9:
                connection.sendall(encode_client_frame(payload, opcode=0xA))

            has_printer = any(
                key_name in merged
                for key_name in ("state", "printId", "usedMaterialLength", "model")
            )
            has_cfs = "boxsInfo" in merged
            has_materials = not include_materials or "retMaterials" in merged
            if has_printer and has_cfs and has_materials:
                break
        if not merged:
            raise LanApiError("no JSON status received from port {}".format(port))
        return merged
    finally:
        connection.close()


def clean_text(value, limit=120):
    if value is None:
        return None
    text = str(value).replace("\r", " ").replace("\n", " ").strip()
    return text[:limit]


def slot_key(box, material):
    box_type = int(box.get("type", 0) or 0)
    if box_type == 1:
        return "EXT"
    box_id = int(box.get("id", 0) or 0)
    material_id = int(material.get("id", 0) or 0)
    letter = chr(ord("A") + material_id) if 0 <= material_id <= 25 else str(material_id)
    return "T{}{}".format(box_id, letter)


def summarize_materials(payload):
    box_info = payload.get("boxsInfo")
    if not isinstance(box_info, dict):
        return [], []
    boxes = box_info.get("materialBoxs")
    if not isinstance(boxes, list):
        return [], []
    slots = []
    selected = []
    for box in boxes:
        if not isinstance(box, dict):
            continue
        materials = box.get("materials")
        if not isinstance(materials, list):
            continue
        for material in materials:
            if not isinstance(material, dict):
                continue
            item = {
                "slot": slot_key(box, material),
                "vendor": clean_text(material.get("vendor")),
                "type": clean_text(material.get("type")),
                "name": clean_text(material.get("name")),
                "color": clean_text(material.get("color"), 16),
                "percent": material.get("percent"),
                "state": material.get("state"),
                "selected": bool(material.get("selected")),
            }
            slots.append(item)
            if item["selected"]:
                selected.append(item["slot"])
    return slots, selected


def summarize(payload, materials_requested=False):
    slots, selected = summarize_materials(payload)
    material_rows = payload.get("retMaterials")
    if not isinstance(material_rows, list):
        material_rows = None
    summary = {
        "printer": {
            "model": clean_text(payload.get("model")),
            "model_version": clean_text(payload.get("modelVersion")),
            "state": payload.get("state"),
            "print_file": clean_text(payload.get("printFileName")),
            "print_id_present": bool(payload.get("printId")),
            "progress_percent": payload.get("printProgress", payload.get("dProgress")),
            "used_material_length_mm": payload.get("usedMaterialLength"),
            "print_left_time_s": payload.get("printLeftTime"),
            "layer": payload.get("layer"),
            "total_layer": payload.get("TotalLayer"),
            "cfs_connect": payload.get("cfsConnect"),
            "webrtc_support": payload.get("webrtcSupport"),
        },
        "cfs": {
            "slots": slots,
            "selected_slots": selected,
            "selection_semantics": "ui_material_selection_not_proof_of_feed_arm",
        },
        "materials": {
            "requested": bool(materials_requested),
            "response_received": material_rows is not None,
            "profile_count": len(material_rows) if material_rows is not None else None,
        },
        "safety": "fixed_get_requests_only_no_set_no_gcode_no_motion_no_heat_no_files",
    }
    return summary


def render_report(report):
    printer = report["printer"]
    cfs = report["cfs"]
    lines = [
        "K2_LAN_API|OK|fixed get-only WebSocket query completed",
        "PRINTER|INFO|model={} version={} state={} progress={} used_material_mm={}".format(
            printer["model"] or "unknown",
            printer["model_version"] or "unknown",
            printer["state"],
            printer["progress_percent"],
            printer["used_material_length_mm"],
        ),
        "PRINT|INFO|id_present={} file={} layer={}/{} left_s={}".format(
            printer["print_id_present"],
            printer["print_file"] or "-",
            printer["layer"],
            printer["total_layer"],
            printer["print_left_time_s"],
        ),
        "CFS|INFO|connected={} slots={} selected={}".format(
            printer["cfs_connect"],
            len(cfs["slots"]),
            ",".join(cfs["selected_slots"]) or "none",
        ),
    ]
    for slot in cfs["slots"]:
        lines.append(
            "CFS_SLOT|INFO|{} vendor={} type={} name={} color={} remain={} selected={}".format(
                slot["slot"],
                slot["vendor"] or "-",
                slot["type"] or "-",
                slot["name"] or "-",
                slot["color"] or "-",
                slot["percent"],
                int(slot["selected"]),
            )
        )
    lines.extend(
        [
            "CFS_SELECTION|INFO|{}".format(cfs["selection_semantics"]),
            "MATERIALS|INFO|requested={} response_received={} profile_count={}".format(
                report["materials"]["requested"],
                report["materials"]["response_received"],
                report["materials"]["profile_count"],
            ),
            "SAFETY|OK|{}".format(report["safety"]),
        ]
    )
    return "\n".join(lines)


def validate_requests():
    encoded = json.dumps(list(SAFE_REQUESTS) + [MATERIAL_REQUEST], sort_keys=True)
    if any(request.get("method") != "get" for request in SAFE_REQUESTS):
        raise LanApiError("unsafe method in fixed request table")
    if MATERIAL_REQUEST.get("method") != "get":
        raise LanApiError("unsafe materials request")
    forbidden = (
        '"method"' + ': "set"',
        "gcode",
        "move",
        "home",
        "temperature",
        "delete",
        "remove",
        "ctrl",
    )
    for token in forbidden:
        if token.lower() in encoded.lower():
            raise LanApiError("unsafe token in fixed request table: {}".format(token))


def selftest():
    validate_requests()
    for length in (0, 1, 125, 126, 65535, 65536):
        frame = encode_client_frame(b"x" * length)
        decoded, remainder = extract_frame(frame)
        if decoded is None or decoded[2] != b"x" * length or remainder:
            raise LanApiError("WebSocket frame selftest failed at length {}".format(length))
    sample = {
        "state": 0,
        "usedMaterialLength": 123.4,
        "boxsInfo": {
            "materialBoxs": [
                {
                    "id": 1,
                    "type": 0,
                    "materials": [
                        {
                            "id": 0,
                            "vendor": "Creality",
                            "type": "PLA",
                            "name": "Hyper PLA",
                            "color": "#000000",
                            "percent": 88,
                            "state": 1,
                            "selected": 1,
                        }
                    ],
                }
            ]
        },
    }
    report = summarize(sample)
    if report["cfs"]["selected_slots"] != ["T1A"]:
        raise LanApiError("CFS slot parser selftest failed")
    serialized = json.dumps(report, sort_keys=True)
    if any(key.lower() in serialized.lower() for key in FORBIDDEN_OUTPUT_KEYS):
        raise LanApiError("sensitive output key selftest failed")
    print("SELFTEST|OK|K2 LAN fixed get-only requests and WebSocket framing")


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=os.environ.get("K2_LAN_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("K2_LAN_PORT", "9999")))
    parser.add_argument("--timeout", type=float, default=4.0)
    parser.add_argument("--include-materials", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    try:
        validate_requests()
        if args.selftest:
            selftest()
            return 0
        payload = fetch_status(
            args.host,
            args.port,
            max(0.5, args.timeout),
            include_materials=args.include_materials,
        )
        report = summarize(payload, materials_requested=args.include_materials)
        if args.json:
            print(json.dumps(report, ensure_ascii=True, sort_keys=True, indent=2))
        else:
            print(render_report(report))
        return 0
    except (LanApiError, OSError, ValueError) as exc:
        print("K2_LAN_API|FAIL|{}".format(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
