#!/bin/sh
# Diagnose or briefly probe the stock Creality nozzle AI camera on K2 Pro/F012.
# Any explicit power test restores the original on-demand standby state.

SCRIPT_DIR="${K2_HELPER_DIR:-/mnt/UDISK/helper-script}"
AI_WORKER="$SCRIPT_DIR/scripts/k2_observability.py"
LOG_DIR=/mnt/UDISK/creality/userdata/log/cam_fw
LOG_FILE=$LOG_DIR/nozzle_camera_recover.log
MASTER_LOG=${K2_MASTER_LOG:-/mnt/UDISK/creality/userdata/log/master-server.log}
SUB_CAMERA_LOG=${K2_SUB_CAMERA_LOG:-/mnt/UDISK/creality/userdata/log/cam_sub_app.log}
PROBE_POWERED_ON=0

log_msg() {
    mkdir -p "$LOG_DIR"
    echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $*" >> "$LOG_FILE"
}

identity_ok() {
    model="$(/usr/bin/get_sn_mac.sh model 2>/dev/null || true)"
    board="$(/usr/bin/get_sn_mac.sh board 2>/dev/null || true)"
    [ "$model" = "F012" ] && [ "$board" = "CR0CN200400C10" ]
}

printer_cold_idle() {
    python3 -B - <<'PYEOF'
import json
import urllib.request

url = (
    "http://127.0.0.1:7125/printer/objects/query"
    "?print_stats&heater_bed&extruder"
)
with urllib.request.urlopen(url, timeout=4) as response:
    status = json.load(response)["result"]["status"]
state = status["print_stats"]["state"]
bed_target = float(status["heater_bed"]["target"])
extruder_target = float(status["extruder"]["target"])
allowed = {"standby", "complete", "cancelled", "error"}
if state not in allowed or bed_target != 0.0 or extruder_target != 0.0:
    raise SystemExit(1)
print(
    "NOZZLE_TEST_SAFE_STATE"
    f"|state={state}|bed_target={bed_target}|extruder_target={extruder_target}"
)
PYEOF
}

ai_status() {
    if [ -f "$AI_WORKER" ] && command -v python3 >/dev/null 2>&1; then
        python3 -B "$AI_WORKER" --ai-status
        return $?
    fi
    echo "AI_STATUS|ERROR|missing $AI_WORKER or python3"
    return 1
}

camera_status_json() {
    ubus call camera status 2>/dev/null || true
}

camera_sub_online() {
    raw="$(camera_status_json)"
    if command -v python3 >/dev/null 2>&1 && [ -n "$raw" ]; then
        printf '%s' "$raw" | python3 -c 'import json,sys; data=json.load(sys.stdin); sys.exit(0 if data.get("cameras",{}).get("camera_sub",{}).get("online") == 1 else 1)' 2>/dev/null && return 0
    fi
    printf '%s\n' "$raw" | grep -A6 '"camera_sub"' | grep -q '"online"[[:space:]]*:[[:space:]]*1'
}

sub_video_nodes() {
    found=0
    for p in /dev/v4l/by-id/*sub* /dev/v4l/by-path/*sub* /dev/v4l/by-id/*nozzle* /dev/v4l/by-path/*nozzle*; do
        [ -e "$p" ] || continue
        found=1
        printf '%s->%s ' "$p" "$(readlink "$p" 2>/dev/null || echo '?')"
    done
    [ "$found" -eq 1 ] || printf 'missing'
}

video_node_list() {
    found=0
    for p in /dev/video*; do
        [ -e "$p" ] || continue
        found=1
        printf '%s ' "$p"
    done
    [ "$found" -eq 1 ] || printf 'missing'
}

sub_video_node_present() {
    for p in /dev/v4l/by-id/*sub* /dev/v4l/by-path/*sub* /dev/v4l/by-id/*nozzle* /dev/v4l/by-path/*nozzle*; do
        [ -e "$p" ] && return 0
    done
    return 1
}

status() {
    ai_status || true
    echo "NOZZLE_GPIO|$(cat /sys/class/gpio/gpio162/value 2>/dev/null || echo missing)"
    echo "NOZZLE_SUB_NODES|$(sub_video_nodes)"
    echo "VIDEO_NODES|$(video_node_list)"
    echo "NOZZLE_LEGACY_NODE|$(readlink /dev/v4l/by-id/sub-video2 2>/dev/null || echo missing)"
    echo "NOZZLE_LEGACY_VIDEO2|$([ -e /dev/video2 ] && echo present || echo missing)"
    camera_status_json
    ps w | grep -E 'cam_sub_app|device_manager' | grep -v grep || true
}

video_nodes() {
    echo ""
    echo "== Video nodes =="
    ls -l /dev/video* /dev/v4l/by-id /dev/v4l/by-path 2>/dev/null || true
    for n in /sys/class/video4linux/video*; do
        [ -e "$n" ] || continue
        echo "$(basename "$n")|name=$(cat "$n/name" 2>/dev/null || echo unknown)"
    done
}

hotplug_map() {
    echo ""
    echo "== Creality USB hotplug camera mapper =="
    if [ -f /etc/hotplug.d/usb/60-v4l ]; then
        ls -l /etc/hotplug.d/usb/60-v4l
        grep -nE 'ACTION|BIND|UVC|video|camera|sub|main|14/|32e6|9221|046d' /etc/hotplug.d/usb/60-v4l 2>/dev/null || sed -n '1,160p' /etc/hotplug.d/usb/60-v4l
    else
        echo "missing: /etc/hotplug.d/usb/60-v4l"
    fi
}

recent_usb_logs() {
    echo ""
    echo "== Recent USB/UVC/BIND/camera log evidence =="
    found=0
    for log in /tmp/log/messages /mnt/UDISK/printer_data/logs/klippy.log /mnt/UDISK/printer_data/logs/moonraker.log /tmp/camera_startup.log "$LOG_FILE"; do
        [ -f "$log" ] || continue
        echo "-- $log"
        tail -n 600 "$log" 2>/dev/null | grep -Ei 'UVC|uvc|BIND|usb|video[0-9]|v4l|camera_sub|camera_main|nozzle|cam_sub|cam_main|32e6|9221|No such device|flowEmDetect' | tail -n 80 || true
        found=1
    done
    [ "$found" -eq 1 ] || echo "no known log file found"
}

recent_ai_events() {
    echo ""
    echo "== Recent Creality AI / PA / Flow / Waste events =="
    event_tmp=/tmp/nozzle_ai_events_$$
    {
        tail -n 30000 "$MASTER_LOG" 2>/dev/null
        tail -n 500 "$SUB_CAMERA_LOG" 2>/dev/null
    } |
        grep -Ei 'PastaDetect|flow_pa result|flow_em best_flow_percentage|flowDetect|flowEmDetect|ai_engine|EMdetection|waste|camera_sub|AC05(04|10|11|12|13|14|15|16)|key564|wait buffer|xioctl' |
        tail -n 100 >"$event_tmp" || true
    if [ -s "$event_tmp" ]; then
        cat "$event_tmp"
    else
        echo "AI_EVENTS|INFO|no matching event in the current bounded log window"
    fi
    rm -f "$event_tmp"
    echo "AI_EVENTS_SCOPE|current master log last 30000 lines plus current sub-camera log; compressed archives are skipped to keep the menu responsive"
    echo "AI_LOG_NOTE|First-frame timeout can be warm-up; xioctl error 19 after power-off is expected when a successful capture/result precedes it."
    camera_log_classification
}

camera_log_classification() {
    master_tmp=/tmp/nozzle_master_classify_$$
    sub_tmp=/tmp/nozzle_sub_classify_$$
    tail -n 30000 "$MASTER_LOG" 2>/dev/null >"$master_tmp" || :
    tail -n 500 "$SUB_CAMERA_LOG" 2>/dev/null >"$sub_tmp" || :

    results=$(grep -Eic 'best_flow_pressure_advance|best_flow_percentage' "$master_tmp" 2>/dev/null || true)
    power_off=$(grep -Eic 'NOZ_CAM_PWR_OFF_CMD' "$master_tmp" 2>/dev/null || true)
    abnormal_zero=$(grep -Eic 'subCameraAbnormal:[[:space:]]*0' "$master_tmp" 2>/dev/null || true)
    abnormal_positive=$(grep -Eic 'subCameraAbnormal:[[:space:]]*[1-9]' "$master_tmp" 2>/dev/null || true)
    hard_fail=$(grep -Eic 'ai flow_(pa|em) detect (fail|capture abnormal|value abnormal)|ai capture (cmd fail|return error)' "$master_tmp" 2>/dev/null || true)
    device_noise=$(grep -Eic 'No such device|xioctl\([^)]*\): error 19' "$sub_tmp" 2>/dev/null || true)
    frame_retry=$(grep -Eic 'wait buffer.*timeout|readframe fail|invalid End Of Image|frame is not valid' "$sub_tmp" 2>/dev/null || true)
    successful_frames=$(grep -Eic 'write_ai_image_group success' "$sub_tmp" 2>/dev/null || true)

    state=clean
    if [ "$abnormal_positive" -gt 0 ] || [ "$hard_fail" -gt 0 ]; then
        state=attention
    elif [ "$device_noise" -gt 0 ] && [ "$power_off" -gt 0 ] &&
        [ "$abnormal_zero" -gt 0 ] && [ "$results" -gt 0 ] &&
        [ "$successful_frames" -gt 0 ]; then
        state=expected_poweroff_noise
    elif [ "$device_noise" -gt 0 ]; then
        state=review_device_loss
    elif [ "$frame_retry" -gt 0 ] && [ "$successful_frames" -gt 0 ]; then
        state=transient_frame_retry
    fi

    echo "NOZZLE_LOG_CLASSIFICATION|state=$state|results=$results|power_off=$power_off|sub_abnormal_zero=$abnormal_zero|sub_abnormal_positive=$abnormal_positive|hard_fail=$hard_fail|device_noise=$device_noise|frame_retry=$frame_retry|successful_frames=$successful_frames"
    rm -f "$master_tmp" "$sub_tmp"
}

udev_video_summary() {
    echo ""
    echo "== udev/video identity summary =="
    if ! command -v udevadm >/dev/null 2>&1; then
        echo "udevadm missing; using sysfs names only"
        for n in /sys/class/video4linux/video*; do
            [ -e "$n" ] || continue
            echo "$(basename "$n")|name=$(cat "$n/name" 2>/dev/null || echo unknown)"
        done
        return 0
    fi
    for n in /dev/video*; do
        [ -e "$n" ] || continue
        echo "-- $n"
        udevadm info -a -n "$n" 2>/dev/null | grep -E 'looking at device|KERNELS==|SUBSYSTEMS==|DRIVERS==|ATTRS?\{(idVendor|idProduct|product|manufacturer|serial|name|index)\}' | head -n 90 || true
    done
}

compact_log_hits() {
    hits=0
    for log in /tmp/log/messages /mnt/UDISK/printer_data/logs/klippy.log /tmp/camera_startup.log "$LOG_FILE"; do
        [ -f "$log" ] || continue
        n=$(tail -n 600 "$log" 2>/dev/null | grep -Eic 'UVC|uvc|BIND|video[0-9]|camera_sub|nozzle|No such device|32e6|9221' || true)
        hits=$((hits + n))
    done
    echo "$hits"
}

diagnose_compact() {
    echo "NOZZLE_USB_DIAG|gpio=$(cat /sys/class/gpio/gpio162/value 2>/dev/null || echo missing)|sub_nodes=$(sub_video_nodes)|video_nodes=$(video_node_list)|legacy_video2=$([ -e /dev/video2 ] && echo present || echo missing)|hotplug=$([ -f /etc/hotplug.d/usb/60-v4l ] && echo present || echo missing)|udevadm=$(command -v udevadm >/dev/null 2>&1 && echo present || echo missing)|recent_usb_log_hits=$(compact_log_hits)"
}

diagnose() {
    echo "K2 Pro nozzle AI camera diagnosis - read-only"
    echo "This does not power-cycle the nozzle camera. Creality keeps it off while idle and enables it for Auto PA, Flow Ratio and selected CFS waste checks."
    echo "First-layer and ongoing print-fault detection use the main/chamber camera."
    echo "Auto PA/Flow also require the per-job Print Calibration option; global flags alone do not start calibration."
    echo "If Fluidd/Mainsail main camera works but Creality Print app hides camera after firmware updates, treat that as app/firmware compatibility first."
    echo "If a USB hub is attached to the chamber-camera path, stock firmware may bind the first device as the chamber camera and leave the nozzle path wrong."
    echo ""
    status
    diagnose_compact
    video_nodes
    hotplug_map
    udev_video_summary
    recent_usb_logs
    recent_ai_events
}

probe_cleanup() {
    if [ "$PROBE_POWERED_ON" -eq 1 ] && [ -x /usr/bin/nozzle_cam_power.sh ]; then
        /usr/bin/nozzle_cam_power.sh off >/dev/null 2>&1 || true
        sleep 4
        PROBE_POWERED_ON=0
        log_msg "probe cleanup: nozzle AI camera returned to standby/off"
    fi
}

probe() {
    if ! identity_ok; then
        log_msg "probe refused: expected exact F012 / CR0CN200400C10"
        echo "NOZZLE_CAMERA_PROBE|REFUSED|unsupported model or board"
        return 1
    fi
    if [ ! -x /usr/bin/nozzle_cam_power.sh ]; then
        log_msg "probe failed: /usr/bin/nozzle_cam_power.sh missing"
        echo "NOZZLE_CAMERA_PROBE|FAIL|power script missing"
        return 1
    fi
    if ! printer_cold_idle; then
        log_msg "probe refused: printer is not cold and idle"
        echo "NOZZLE_CAMERA_PROBE|REFUSED|printer must be idle with heater targets at 0"
        return 1
    fi
    if camera_sub_online && sub_video_node_present; then
        log_msg "probe skipped: nozzle AI camera already active; ownership left to Creality"
        echo "NOZZLE_CAMERA_PROBE|SKIP|camera already active; no power command sent"
        status
        return 0
    fi

    echo "NOZZLE_CAMERA_PROBE|START|power-only test; no motion, heating or AI calibration"
    log_msg "probe: starting controlled on/off self-test"
    trap probe_cleanup 0
    trap 'exit 130' 1 2 15

    /usr/bin/nozzle_cam_power.sh on
    PROBE_POWERED_ON=1
    elapsed=0
    online=0
    while [ "$elapsed" -lt 20 ]; do
        if camera_sub_online && sub_video_node_present; then
            online=1
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    if [ "$online" -eq 1 ]; then
        echo "NOZZLE_CAMERA_PROBE|ONLINE|after=${elapsed}s"
        log_msg "probe: camera online after ${elapsed}s"
    else
        echo "NOZZLE_CAMERA_PROBE|FAIL|camera did not become ready within 20s"
        log_msg "probe failed: camera did not become ready within 20s"
    fi

    probe_cleanup
    settled=0
    while [ "$settled" -lt 10 ]; do
        if ! camera_sub_online && ! sub_video_node_present; then
            break
        fi
        sleep 1
        settled=$((settled + 1))
    done
    trap - 0 1 2 15

    status
    if [ "$online" -eq 1 ] && ! camera_sub_online && ! sub_video_node_present; then
        echo "NOZZLE_CAMERA_PROBE|OK|camera tested and restored to on-demand standby"
        log_msg "probe ok: camera tested and restored to standby"
        return 0
    fi
    echo "NOZZLE_CAMERA_PROBE|FAIL|test or standby restoration incomplete"
    log_msg "probe failed: test or standby restoration incomplete"
    return 1
}

recover() {
    echo "NOZZLE_CAMERA_RECOVER_COMPAT|The old recover command now performs the safer temporary probe and always restores standby."
    probe
}

standby() {
    if ! identity_ok; then
        log_msg "standby refused: expected exact F012 / CR0CN200400C10"
        echo "NOZZLE_CAMERA_STANDBY|REFUSED|unsupported model or board"
        return 1
    fi

    if [ ! -x /usr/bin/nozzle_cam_power.sh ]; then
        log_msg "fail standby: /usr/bin/nozzle_cam_power.sh missing"
        status
        return 1
    fi
    if ! printer_cold_idle; then
        log_msg "standby refused: printer is not cold and idle"
        echo "NOZZLE_CAMERA_STANDBY|REFUSED|printer must be idle with heater targets at 0"
        return 1
    fi

    log_msg "standby: leaving nozzle AI camera off for Creality on-demand control"
    /usr/bin/nozzle_cam_power.sh off
    sleep 5
    status
}

boot_status_only() {
    sleep 55
    log_msg "boot: status only; use restart/recover for explicit power-cycle"
    status
}

case "${1:-status}" in
    status) status ;;
    diagnose|diag|usb-diagnose) diagnose ;;
    diagnose-compact|compact) diagnose_compact ;;
    log-classify|log-status) camera_log_classification ;;
    ai-status|readiness|calibration-status) ai_status ;;
    probe|selftest) probe ;;
    recover) recover ;;
    restart) recover ;;
    standby|off) standby ;;
    boot) boot_status_only ;;
    *) echo "Usage: $0 {status|diagnose|diagnose-compact|log-classify|ai-status|probe|recover|restart|standby|off|boot}" ; exit 1 ;;
esac
