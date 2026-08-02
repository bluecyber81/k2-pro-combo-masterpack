#!/bin/sh
# preflight_k2pro.sh - non-destructive K2 Pro Combo report
SCRIPT_DIR=/mnt/UDISK/helper-script
PRINTER_DATA=/mnt/UDISK/printer_data
CONFIG_DIR=$PRINTER_DATA/config
LOGS_DIR=$PRINTER_DATA/logs
REPORT_DIR=$PRINTER_DATA/backups/k2pro_helper
REPORT=$REPORT_DIR/k2pro_preflight_report.txt
mkdir -p "$REPORT_DIR"
{
  echo "K2 Pro Combo Helper preflight report - v5.2.21.91-auto-addr-recovery firmware aware"
  echo "Date: $(date)"
  echo "Hostname: $(hostname 2>/dev/null)"
  echo "Kernel: $(uname -a 2>/dev/null)"
  echo "Arch: $(uname -m 2>/dev/null)"
  echo "Helper header: $(head -n 2 "$SCRIPT_DIR/helper.sh" 2>/dev/null | tail -n 1)"
  echo "Firmware env version: $(fw_printenv version 2>/dev/null | cut -d= -f2)"
  echo "Model from get_sn_mac: $(/usr/bin/get_sn_mac.sh model 2>/dev/null)"
  echo "Board from get_sn_mac: $(/usr/bin/get_sn_mac.sh board 2>/dev/null)"
  echo "Structure version: $(/usr/bin/get_sn_mac.sh structure_version 2>/dev/null)"
  echo ""
  echo "== Firmware V1.1.5.5 / V1.1.6.x model mapping reference =="
  echo "F008=K2Plus, F012=K2Pro, F021=K2, F025=M300, GS-04=GS04, Z2=Z2"
  echo "Expected for K2 Pro Combo: model=F012, board=CR0CN200400C10, Printer_size=300*300*300"
  echo "Reviewed live runtime baseline from 2026-07-31: firmware=1.1.6.7 on exact F012/CR0CN200400C10 and CFS/T1=1.5.0."
  echo ""
  echo "== Handover / Expert Full-Control profile =="
  echo "- Expert Full-Control tools are present; use them deliberately, not by accident."
  echo "- CFS material movement stays on the display/Creality workflow, slicer toolchange and stock M8200/CR_BOX path."
  echo "- Raw/direct CFS/G-code control is not part of this normal build; use display, slicer and stock CFS workflows."
  echo "- SAVE_CONFIG pending only auto_addr is expected with Creality/CFS and should not be saved just for that."
  echo "- Nozzle-AI camera can be diagnosed read-only or power-recovered explicitly with --nozzle-camera-recover."
  echo "- Creality Timelapse Recover is preferred over Moonraker Timelapse on this printer."
  echo "- KAMP-K2 install/repair is available; check start/end/CFS workflows after changes."
  echo ""
  echo "== Installed helper features =="
  if [ -f "$SCRIPT_DIR/.installed" ]; then
    cat "$SCRIPT_DIR/.installed"
  else
    echo "No .installed file found"
  fi
  echo ""
  echo "== Files =="
  for f in printer.cfg printer_params.cfg gcode_macro.cfg box.cfg sensorless.cfg factory_printer.cfg moonraker.conf; do
    if [ -f "$CONFIG_DIR/$f" ]; then
      echo "FOUND $CONFIG_DIR/$f ($(wc -c < "$CONFIG_DIR/$f") bytes)"
    else
      echo "MISSING $CONFIG_DIR/$f"
    fi
  done
  echo ""
  echo "== Moonraker / G-code metadata queue =="
  grep -n "^CONF=" /etc/init.d/moonraker /etc/rc.d/S56moonraker 2>/dev/null
  grep -n "include\|queue_gcode_uploads\|update_manager\|enable_system_updates" \
    /usr/share/moonraker/moonraker.conf "$CONFIG_DIR/moonraker.conf" 2>/dev/null
  if grep -Eq "^[[:space:]]*queue_gcode_uploads:[[:space:]]*False[[:space:]]*$" /usr/share/moonraker/moonraker.conf 2>/dev/null; then
    echo "warning: queue_gcode_uploads is False; Fluidd/Mainsail can show missing preview or metadata while files are scanned"
  fi
  echo ""
  echo "== Product / bed size =="
  grep -n "F008\|F012\|Printer_size\|variable_bed_size\|position_max\|mesh_min\|mesh_max" "$CONFIG_DIR"/*.cfg 2>/dev/null | head -160
  echo ""
  echo "== CFS / Box =="
  grep -n "\[include box.cfg\]\|\[box\|BOX_\|box_" "$CONFIG_DIR"/*.cfg 2>/dev/null | head -120
  echo ""
  echo "== Live CFS / Box API =="
  python3 - << 'PYEOF' 2>/dev/null || echo "Moonraker live CFS query failed"
import json
import urllib.request
url = "http://127.0.0.1:7125/printer/objects/query?box&motor_control&filament_switch_sensor%20filament_sensor&configfile"
with urllib.request.urlopen(url, timeout=5) as response:
    status = json.loads(response.read().decode()).get("result", {}).get("status", {})
box = status.get("box", {})
motor = status.get("motor_control", {})
sensor = status.get("filament_switch_sensor filament_sensor", {})
configfile = status.get("configfile", {})
pending_items = configfile.get("save_config_pending_items", {}) or {}
pending_names = sorted(pending_items.keys())
print("box.state=%s enable=%s auto_refill=%s filament_useup=%s" % (
    box.get("state"), box.get("enable"), box.get("auto_refill"), box.get("filament_useup")
))
print("T1.state=%s T1.version=%s T1.sn=%s" % (
    box.get("T1", {}).get("state"), box.get("T1", {}).get("version"), box.get("T1", {}).get("sn")
))
print("motor_ready=%s filament_sensor_enabled=%s filament_detected=%s" % (
    motor.get("motor_ready"), sensor.get("enabled"), sensor.get("filament_detected")
))
print("save_config_pending=%s pending_items=%s auto_addr_only_pending=%s" % (
    configfile.get("save_config_pending"), ",".join(pending_names), pending_names == ["auto_addr"]
))
if pending_names == ["auto_addr"]:
    print("warning: only auto_addr is pending; do not run SAVE_CONFIG just for this Creality CFS state")
PYEOF
  echo ""
  echo "== Motorcontroller status (strictly read-only) =="
  if [ -x "$SCRIPT_DIR/scripts/motor_controller_report.sh" ]; then
    K2_HELPER_DIR="$SCRIPT_DIR" sh "$SCRIPT_DIR/scripts/motor_controller_report.sh" || true
  else
    echo "motor_controller_report.sh missing"
  fi
  echo ""
  echo "== CFS direct-load safety note =="
  echo "The official box.cfg direct BOX_LOAD_MATERIAL path calls BOX_EXTRUDE_MATERIAL."
  echo "On this printer this path triggered key60/Internal error and a Klipper shutdown during live test."
  echo "Use this helper for diagnosis only; do not run direct BOX_LOAD_MATERIAL/BOX_EXTRUDE_MATERIAL tests from Moonraker."
  if [ -f "$LOGS_DIR/klippy.log" ]; then
    echo "Recent key60/BOX_EXTRUDE_MATERIAL hits: $(tail -n 2000 "$LOGS_DIR/klippy.log" | grep -Ei 'key60|Internal error|No active exception to reraise|BOX_LOAD_MATERIAL|BOX_EXTRUDE_MATERIAL|BOX_SEND_DATA|BOX_INFO_REFRESH|_CFS_LOAD|_CFS_UNLOAD' | grep -Eiv '_handle_query|objects/query|configfile|gcode_macro|save_config_pending' | wc -l | awk '{print $1}')"
    echo "Recent motor_control_wrapper ready-callback hits: $(tail -n 3000 "$LOGS_DIR/klippy.log" | grep -Ec 'motor_control_wrapper\.Motor_Control\.set_motor_pin|No active exception to reraise|Internal error during ready callback')"
    echo "Recent buf_len noise hits: $(tail -n 500 "$LOGS_DIR/klippy.log" | grep -c 'buf_len = 0x')"
  fi
  echo ""
  echo "== CFS command/log safety scan =="
  if [ -f "$SCRIPT_DIR/scripts/cfs_safety_scan.sh" ]; then
    sh "$SCRIPT_DIR/scripts/cfs_safety_scan.sh" --compact 2>/dev/null
    echo "Run helper.sh --cfs-safety-scan for detailed file and log hits."
  else
    echo "cfs_safety_scan.sh missing"
  fi
  echo ""
  echo "== CFS protocol/slot summary =="
  if [ -f "$SCRIPT_DIR/scripts/cfs_protocol_report.sh" ]; then
    if ! sh "$SCRIPT_DIR/scripts/cfs_protocol_report.sh" --compact 2>/dev/null; then
      echo "CFS_PROTOCOL_SUMMARY_RESULT=partial_or_unavailable"
    fi
    echo "Run helper.sh --cfs-protocol-report for slot, database and command-policy details."
  else
    echo "cfs_protocol_report.sh missing"
  fi
  echo ""
  echo "== K2 Pro protection guard =="
  if [ -x "$SCRIPT_DIR/scripts/k2pro_protection_guard.sh" ]; then
    sh "$SCRIPT_DIR/scripts/k2pro_protection_guard.sh" compact 2>/dev/null || true
    echo "Run helper.sh --protection-status for firmware, config drift, recovery, database and passive CFS details."
  else
    echo "k2pro_protection_guard.sh missing"
  fi
  echo ""
  echo "== Handover baseline compact check =="
  if [ -f "$SCRIPT_DIR/scripts/handover_baseline_k2pro.sh" ]; then
    sh "$SCRIPT_DIR/scripts/handover_baseline_k2pro.sh" --compact 2>/dev/null || true
  else
    echo "handover_baseline_k2pro.sh missing"
  fi
  echo ""
  echo "== Existing gcode_macro names =="
  grep -Rnh '^\[gcode_macro' "$CONFIG_DIR" 2>/dev/null | sed 's/^/  /' | head -220
  echo ""
  echo "== Fan / chamber sections =="
  grep -RnhE '^\[output_pin fan|^\[heater_generic chamber|^\[heater_fan chamber|^\[temperature_fan chamber|scale:' "$CONFIG_DIR" 2>/dev/null | head -160
  echo ""
  echo "== Services =="
  ls -l /etc/rc.d/S55klipper /etc/rc.d/S56moonraker /etc/rc.d/S80nginx /etc/rc.d/S97webrtc /etc/init.d/moonraker 2>/dev/null
  [ -x /etc/rc.d/S99camera ] && /etc/rc.d/S99camera status 2>/dev/null
  echo ""
  echo "== go2rtc / main camera reference =="
  if [ -f "$SCRIPT_DIR/go2rtc.yaml" ]; then
    grep -n "k2camera\|format=creality\|webrtc" "$SCRIPT_DIR/go2rtc.yaml" 2>/dev/null || true
    if grep -q "#format=creality" "$SCRIPT_DIR/go2rtc.yaml" 2>/dev/null; then
      echo "main_camera_mode=direct_go2rtc_format_creality"
      echo "k2rtc_bridge_required=no"
    else
      echo "main_camera_mode=legacy_or_bridge; check camera health"
    fi
  else
    echo "go2rtc.yaml missing"
  fi
  echo ""
  echo "== Spoolman CFS sync map reference =="
  if [ -f "$SCRIPT_DIR/spoolman_cfs_map.json" ]; then
    python3 - "$SCRIPT_DIR/spoolman_cfs_map.json" << 'PYEOF' 2>/dev/null || echo "spoolman map parse failed"
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text())
slots = ["T1A", "T1B", "T1C", "T1D"]
print("map_enabled=%s" % data.get("enabled"))
print("map_slots=%s" % ",".join("%s:%s" % (s, data.get(s)) for s in slots))
complete = all(str(data.get(s) or "").isdigit() and int(str(data.get(s))) > 0 for s in slots)
if data.get("enabled") is None and complete:
    print("map_legacy_enabled=True")
ids_1_to_4 = all(str(data.get(s)) == str(i) for i, s in enumerate(slots, 1))
print("map_ids_1_to_4=%s" % ids_1_to_4)
if ids_1_to_4:
    print("note: IDs 1-4 can be real Spoolman spool IDs; live test on 192.168.178.74 confirmed this pattern")
PYEOF
  elif [ -f "$SCRIPT_DIR/spoolman_cfs_map.example.json" ]; then
    echo "active_map=missing_or_preserved_existing"
    echo "example_map=$SCRIPT_DIR/spoolman_cfs_map.example.json"
    echo "status_command=$SCRIPT_DIR/helper.sh --spoolman-cfs-status"
  else
    echo "active_map=missing"
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 6 http://127.0.0.1:7125/server/spoolman/status 2>/dev/null || true
  fi
  if [ -x "$SCRIPT_DIR/scripts/nozzle_camera_recover.sh" ]; then
    echo ""
    echo "== Nozzle AI / Auto PA / Flow compact diagnosis =="
    echo "Read-only. Offline/standby is normal while idle; Creality starts this camera for Auto PA, Flow Ratio and selected CFS waste checks."
    echo "First-layer and ongoing print-fault detection use the main/chamber camera."
    sh "$SCRIPT_DIR/scripts/nozzle_camera_recover.sh" ai-status 2>/dev/null || true
    sh "$SCRIPT_DIR/scripts/nozzle_camera_recover.sh" diagnose-compact 2>/dev/null || true
    echo "Run helper.sh --nozzle-camera-diagnose for full USB hotplug, /dev/video and recent UVC/BIND log details."
  fi
  if [ -x "$SCRIPT_DIR/scripts/filament_calibration.sh" ]; then
    echo ""
    echo "== Filament Auto PA / Flow result status =="
    echo "Read-only. Runtime/CFS defaults are labelled separately from confirmed nozzle-camera measurements."
    sh "$SCRIPT_DIR/scripts/filament_calibration.sh" status 2>/dev/null || true
  fi
  echo ""
  echo "== Mounts / free space =="
  df -h / /mnt/UDISK 2>/dev/null
} > "$REPORT"

echo "Preflight report written to: $REPORT"
echo "Upload this file if you want the next patch to be matched to the printer exactly."
