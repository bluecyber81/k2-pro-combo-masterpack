#!/usr/bin/env python3
"""Read-only bed mesh analysis for the Creality K2 Pro.

The tool reads an already existing Moonraker bed_mesh object. It never homes,
heats, probes, moves, or sends G-code.
"""

import argparse
import json
import math
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


DEFAULT_MOONRAKER_URL = os.environ.get(
    "BED_MESH_MOONRAKER_URL",
    os.environ.get("MOONRAKER_URL", "http://127.0.0.1:7125"),
)
QUERY_PATH = "/printer/objects/query?bed_mesh&print_stats&toolhead&extruder&heater_bed"


class MeshError(RuntimeError):
    """Raised when a mesh cannot be fetched or analyzed."""


def solve_3x3(matrix, vector):
    augmented = [
        [float(matrix[row][column]) for column in range(3)] + [float(vector[row])]
        for row in range(3)
    ]
    for column in range(3):
        pivot = max(range(column, 3), key=lambda row: abs(augmented[row][column]))
        if abs(augmented[pivot][column]) < 1e-12:
            raise MeshError("bed mesh plane fit is singular")
        augmented[column], augmented[pivot] = augmented[pivot], augmented[column]
        divisor = augmented[column][column]
        augmented[column] = [value / divisor for value in augmented[column]]
        for row in range(3):
            if row == column:
                continue
            factor = augmented[row][column]
            augmented[row] = [
                augmented[row][index] - factor * augmented[column][index]
                for index in range(4)
            ]
    return [augmented[row][3] for row in range(3)]


def extract_status(payload):
    if not isinstance(payload, dict):
        raise MeshError("Moonraker response is not a JSON object")
    result = payload.get("result", payload)
    if isinstance(result, dict):
        status = result.get("status", result)
    else:
        status = result
    if not isinstance(status, dict):
        raise MeshError("Moonraker response has no status object")
    return status


def normalize_matrix(value):
    if not isinstance(value, list) or len(value) < 2:
        raise MeshError("no usable probed_matrix is stored")
    width = None
    matrix = []
    for row in value:
        if not isinstance(row, list) or len(row) < 2:
            raise MeshError("probed_matrix is not rectangular")
        if width is None:
            width = len(row)
        elif len(row) != width:
            raise MeshError("probed_matrix is not rectangular")
        converted = []
        for item in row:
            try:
                number = float(item)
            except (TypeError, ValueError) as exc:
                raise MeshError("probed_matrix contains a non-numeric value") from exc
            if not math.isfinite(number):
                raise MeshError("probed_matrix contains a non-finite value")
            converted.append(number)
        matrix.append(converted)
    return matrix


def pair(value, fallback):
    if isinstance(value, (list, tuple)) and len(value) >= 2:
        try:
            return [float(value[0]), float(value[1])]
        except (TypeError, ValueError):
            pass
    return list(fallback)


def analyze_payload(payload):
    status = extract_status(payload)
    mesh = status.get("bed_mesh")
    if not isinstance(mesh, dict):
        raise MeshError("Moonraker returned no bed_mesh object")
    matrix = normalize_matrix(mesh.get("probed_matrix"))
    rows = len(matrix)
    columns = len(matrix[0])
    mesh_min = pair(mesh.get("mesh_min"), (0.0, 0.0))
    mesh_max = pair(mesh.get("mesh_max"), (columns - 1.0, rows - 1.0))
    if mesh_max[0] <= mesh_min[0] or mesh_max[1] <= mesh_min[1]:
        raise MeshError("invalid bed mesh dimensions")

    points = []
    for row, values in enumerate(matrix):
        y = mesh_min[1] + (mesh_max[1] - mesh_min[1]) * row / (rows - 1)
        for column, z_value in enumerate(values):
            x = mesh_min[0] + (mesh_max[0] - mesh_min[0]) * column / (columns - 1)
            points.append((x, y, z_value))

    count = len(points)
    sum_x = sum(point[0] for point in points)
    sum_y = sum(point[1] for point in points)
    sum_z = sum(point[2] for point in points)
    normal_matrix = [
        [sum(point[0] ** 2 for point in points), sum(point[0] * point[1] for point in points), sum_x],
        [sum(point[0] * point[1] for point in points), sum(point[1] ** 2 for point in points), sum_y],
        [sum_x, sum_y, count],
    ]
    normal_vector = [
        sum(point[0] * point[2] for point in points),
        sum(point[1] * point[2] for point in points),
        sum_z,
    ]
    slope_x, slope_y, intercept = solve_3x3(normal_matrix, normal_vector)
    residuals = [
        z_value - (slope_x * x + slope_y * y + intercept)
        for x, y, z_value in points
    ]
    raw_values = [point[2] for point in points]
    residual_min = min(residuals)
    residual_max = max(residuals)
    residual_min_index = residuals.index(residual_min)
    residual_max_index = residuals.index(residual_max)
    raw_min_index = raw_values.index(min(raw_values))
    raw_max_index = raw_values.index(max(raw_values))
    residual_rms = math.sqrt(sum(value * value for value in residuals) / count)
    residual_peak_to_peak = residual_max - residual_min
    raw_range = max(raw_values) - min(raw_values)
    x_delta = slope_x * (mesh_max[0] - mesh_min[0])
    y_delta = slope_y * (mesh_max[1] - mesh_min[1])
    edge_residuals = []
    center_residuals = []
    for index, residual in enumerate(residuals):
        row = index // columns
        column = index % columns
        if row in (0, rows - 1) or column in (0, columns - 1):
            edge_residuals.append(residual)
        if (
            rows // 3 <= row <= (2 * rows - 1) // 3
            and columns // 3 <= column <= (2 * columns - 1) // 3
        ):
            center_residuals.append(residual)
    edge_mean = sum(edge_residuals) / len(edge_residuals)
    center_mean = sum(center_residuals) / len(center_residuals)
    center_minus_edge = center_mean - edge_mean
    if center_minus_edge < -0.05:
        shape_hint = "center lower than perimeter after plane removal"
    elif center_minus_edge > 0.05:
        shape_hint = "center higher than perimeter after plane removal"
    else:
        shape_hint = "no strong center-versus-perimeter pattern"

    if residual_peak_to_peak <= 0.10:
        shape_level = "OK"
        shape = "low residual deformation"
    elif residual_peak_to_peak <= 0.20:
        shape_level = "INFO"
        shape = "moderate residual deformation"
    else:
        shape_level = "WARN"
        shape = "high residual deformation"

    if max(abs(x_delta), abs(y_delta)) <= 0.15:
        tilt_level = "OK"
        tilt = "low fitted tilt"
    elif max(abs(x_delta), abs(y_delta)) <= 0.30:
        tilt_level = "INFO"
        tilt = "moderate fitted tilt"
    else:
        tilt_level = "WARN"
        tilt = "high fitted tilt"

    print_stats = status.get("print_stats")
    print_state = print_stats.get("state") if isinstance(print_stats, dict) else None
    heater_bed = status.get("heater_bed")
    if not isinstance(heater_bed, dict):
        heater_bed = {}
    return {
        "profile": str(mesh.get("profile_name") or "unknown"),
        "grid": {"rows": rows, "columns": columns, "samples": count},
        "area": {"min": mesh_min, "max": mesh_max},
        "raw": {
            "minimum_mm": min(raw_values),
            "maximum_mm": max(raw_values),
            "range_mm": raw_range,
            "minimum_xy": list(points[raw_min_index][:2]),
            "maximum_xy": list(points[raw_max_index][:2]),
        },
        "plane": {
            "slope_x_mm_per_mm": slope_x,
            "slope_y_mm_per_mm": slope_y,
            "delta_x_mm": x_delta,
            "delta_y_mm": y_delta,
            "intercept_mm": intercept,
            "level": tilt_level,
            "assessment": tilt,
        },
        "residual": {
            "minimum_mm": residual_min,
            "maximum_mm": residual_max,
            "peak_to_peak_mm": residual_peak_to_peak,
            "rms_mm": residual_rms,
            "max_abs_mm": max(abs(value) for value in residuals),
            "minimum_xy": list(points[residual_min_index][:2]),
            "maximum_xy": list(points[residual_max_index][:2]),
            "center_mean_mm": center_mean,
            "edge_mean_mm": edge_mean,
            "center_minus_edge_mm": center_minus_edge,
            "shape_hint": shape_hint,
            "level": shape_level,
            "assessment": shape,
        },
        "corners": {
            "front_left_mm": matrix[0][0],
            "front_right_mm": matrix[0][-1],
            "rear_left_mm": matrix[-1][0],
            "rear_right_mm": matrix[-1][-1],
        },
        "printer_state": print_state or "unknown",
        "current_bed": {
            "temperature_c": heater_bed.get("temperature"),
            "target_c": heater_bed.get("target"),
        },
        "safety": "read_only_existing_mesh_no_motion_no_heat_no_probe_no_gcode",
    }


def make_query_url(base_url):
    parsed = urllib.parse.urlparse(base_url)
    if parsed.scheme not in ("http", "https"):
        raise MeshError("Moonraker URL must use http or https")
    if parsed.path.startswith("/printer/objects/query"):
        return base_url
    return base_url.rstrip("/") + QUERY_PATH


def fetch_payload(base_url, timeout):
    url = make_query_url(base_url)
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/json", "User-Agent": "K2-Bed-Mesh-Insights/1"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.load(response)
    except (OSError, ValueError, urllib.error.URLError) as exc:
        raise MeshError("could not read Moonraker bed mesh: {}".format(exc)) from exc


def render_report(report):
    grid = report["grid"]
    area = report["area"]
    raw = report["raw"]
    plane = report["plane"]
    residual = report["residual"]
    lines = [
        "BED_MESH|OK|profile={} grid={}x{} samples={} area=({:.1f},{:.1f})-({:.1f},{:.1f})".format(
            report["profile"],
            grid["columns"],
            grid["rows"],
            grid["samples"],
            area["min"][0],
            area["min"][1],
            area["max"][0],
            area["max"][1],
        ),
        "RAW_RANGE|INFO|min={:.4f}mm max={:.4f}mm range={:.4f}mm".format(
            raw["minimum_mm"],
            raw["maximum_mm"],
            raw["range_mm"],
        ),
        "PLANE_TILT|{}|x_delta={:+.4f}mm y_delta={:+.4f}mm {}".format(
            plane["level"],
            plane["delta_x_mm"],
            plane["delta_y_mm"],
            plane["assessment"],
        ),
        "RESIDUAL_SHAPE|{}|rms={:.4f}mm max_abs={:.4f}mm peak_to_peak={:.4f}mm {}".format(
            residual["level"],
            residual["rms_mm"],
            residual["max_abs_mm"],
            residual["peak_to_peak_mm"],
            residual["assessment"],
        ),
        "RESIDUAL_EXTREMA|INFO|min={:+.4f}mm@({:.1f},{:.1f}) max={:+.4f}mm@({:.1f},{:.1f})".format(
            residual["minimum_mm"],
            residual["minimum_xy"][0],
            residual["minimum_xy"][1],
            residual["maximum_mm"],
            residual["maximum_xy"][0],
            residual["maximum_xy"][1],
        ),
        "SHAPE_HINT|INFO|center_minus_edge={:+.4f}mm {}".format(
            residual["center_minus_edge_mm"],
            residual["shape_hint"],
        ),
        "PRINTER_STATE|INFO|{} current_bed={}C target={}C".format(
            report["printer_state"],
            report["current_bed"]["temperature_c"],
            report["current_bed"]["target_c"],
        ),
        "SAFETY|OK|{}".format(report["safety"]),
        "NOTE|INFO|Stored mesh is a historical measurement, not a live probe result.",
        "NOTE|INFO|Mesh tilt is not a screw-turn instruction; confirm mechanically before adjustment.",
    ]
    return "\n".join(lines)


def selftest():
    plane = [[0.01 * x + 0.02 * y for x in range(5)] for y in range(5)]
    plane_payload = {
        "result": {
            "status": {
                "bed_mesh": {
                    "profile_name": "selftest-plane",
                    "mesh_min": [0, 0],
                    "mesh_max": [40, 40],
                    "probed_matrix": plane,
                }
            }
        }
    }
    plane_report = analyze_payload(plane_payload)
    if plane_report["residual"]["max_abs_mm"] > 1e-9:
        raise MeshError("selftest plane residual is not zero")

    bowl = []
    for y in range(5):
        row = []
        for x in range(5):
            row.append(0.03 * ((x - 2) ** 2 + (y - 2) ** 2))
        bowl.append(row)
    bowl_payload = {
        "bed_mesh": {
            "mesh_min": [0, 0],
            "mesh_max": [40, 40],
            "probed_matrix": bowl,
        }
    }
    bowl_report = analyze_payload(bowl_payload)
    if bowl_report["residual"]["peak_to_peak_mm"] < 0.10:
        raise MeshError("selftest bowl deformation was not detected")
    print("SELFTEST|OK|bed mesh plane and residual analysis")


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=DEFAULT_MOONRAKER_URL)
    parser.add_argument("--input", help="read a saved Moonraker JSON response")
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--json", action="store_true", help="emit JSON instead of text")
    parser.add_argument("--selftest", action="store_true")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    try:
        if args.selftest:
            selftest()
            return 0
        if args.input:
            with open(args.input, "r", encoding="utf-8") as source:
                payload = json.load(source)
        else:
            payload = fetch_payload(args.url, args.timeout)
        report = analyze_payload(payload)
        if args.json:
            print(json.dumps(report, ensure_ascii=True, sort_keys=True, indent=2))
        else:
            print(render_report(report))
        return 0
    except (MeshError, OSError, ValueError) as exc:
        print("BED_MESH|FAIL|{}".format(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
