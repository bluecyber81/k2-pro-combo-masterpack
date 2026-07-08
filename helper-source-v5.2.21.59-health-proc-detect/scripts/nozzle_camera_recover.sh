#!/bin/sh
# Recover, park or diagnose the stock Creality nozzle AI camera on K2 Pro/F012.
# Expert-full: restart performs the same controlled power recovery as recover.

LOG_DIR=/mnt/UDISK/creality/userdata/log/cam_fw
LOG_FILE=$LOG_DIR/nozzle_camera_recover.log

log_msg() {
    mkdir -p "$LOG_DIR"
    echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $*" >> "$LOG_FILE"
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
    echo "This does not power-cycle the nozzle camera. Creality may keep it off/standby while idle and enable it only for AI, flow or first-layer checks."
    echo "If Fluidd/Mainsail main camera works but Creality Print app hides camera after firmware updates, treat that as app/firmware compatibility first."
    echo "If a USB hub is attached to the chamber-camera path, stock firmware may bind the first device as the chamber camera and leave the nozzle path wrong."
    echo ""
    status
    diagnose_compact
    video_nodes
    hotplug_map
    udev_video_summary
    recent_usb_logs
}

recover() {
    model="$(get_sn_mac.sh model 2>/dev/null)"
    if [ "$model" != "F012" ] && [ "$model" != "F021" ]; then
        log_msg "skip: unsupported model $model"
        status
        return 0
    fi

    if camera_sub_online && sub_video_node_present; then
        log_msg "ok: nozzle AI camera already online"
        status
        return 0
    fi

    if [ ! -x /usr/bin/nozzle_cam_power.sh ]; then
        log_msg "fail: /usr/bin/nozzle_cam_power.sh missing"
        status
        return 1
    fi

    log_msg "recover: toggling nozzle AI camera power"
    /usr/bin/nozzle_cam_power.sh off
    sleep 4
    /usr/bin/nozzle_cam_power.sh on
    sleep 18

    status
    if camera_sub_online && sub_video_node_present; then
        log_msg "ok: nozzle AI camera recovered"
        return 0
    fi

    log_msg "fail: nozzle AI camera still offline"
    return 1
}

standby() {
    model="$(get_sn_mac.sh model 2>/dev/null)"
    if [ "$model" != "F012" ] && [ "$model" != "F021" ]; then
        log_msg "skip standby: unsupported model $model"
        status
        return 0
    fi

    if [ ! -x /usr/bin/nozzle_cam_power.sh ]; then
        log_msg "fail standby: /usr/bin/nozzle_cam_power.sh missing"
        status
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
    recover) recover ;;
    restart) recover ;;
    standby|off) standby ;;
    boot) boot_status_only ;;
    *) echo "Usage: $0 {status|diagnose|diagnose-compact|recover|restart|standby|off|boot}" ; exit 1 ;;
esac
