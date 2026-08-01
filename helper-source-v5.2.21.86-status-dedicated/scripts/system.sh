#!/bin/sh
# system.sh - Service management and system utilities for K2 Series Helper Script

SCRIPT_DIR=/mnt/UDISK/helper-script
CONFIG_DIR=/mnt/UDISK/printer_data/config
LOGS_DIR=/mnt/UDISK/printer_data/logs
INSTALLED_FILE=$SCRIPT_DIR/.installed

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { printf "%b\n" "${GREEN}[INFO]${NC} $1"; }
log_warn()    { printf "%b\n" "${YELLOW}[WARN]${NC} $1"; }
log_error()   { printf "%b\n" "${RED}[ERROR]${NC} $1"; }
log_success() { printf "%b\n" "${GREEN}[OK]${NC} $1"; }

# ── Service restarts ──────────────────────────────────────────────────────────

is_k2pro_cfs_stack() {
    grep -qs '^\[include box\.cfg\]' "$CONFIG_DIR/printer.cfg" 2>/dev/null && \
    grep -qs '^\[include motor_control\.cfg\]' "$CONFIG_DIR/printer.cfg" 2>/dev/null
}

current_print_state() {
    python3 - <<'PYEOF' 2>/dev/null
import json
import urllib.request

try:
    with urllib.request.urlopen(
        "http://127.0.0.1:7125/printer/objects/query?print_stats", timeout=3
    ) as response:
        payload = json.load(response)
    print(payload["result"]["status"]["print_stats"].get("state", "unknown"))
except Exception:
    print("unknown")
PYEOF
}

schedule_k2pro_reboot() {
    delay="${K2PRO_REBOOT_DELAY:-15}"
    state="$(current_print_state)"
    case "$state" in
        printing|paused)
            log_error "Full reboot refused while print state is '$state'."
            log_warn "Finish or cancel the print, then run the action again."
            return 1
            ;;
        unknown)
            log_warn "Moonraker print state could not be confirmed; no active print was reported."
            ;;
    esac

    touch /tmp/k2pro_helper_reboot_required 2>/dev/null || true
    if [ "${K2PRO_DEFER_REBOOT:-0}" = "1" ]; then
        log_warn "K2/CFS full reboot is required but was deferred by K2PRO_DEFER_REBOOT=1."
        return 0
    fi

    log_warn "K2 Pro Combo uses a full Linux reboot instead of an isolated Klipper restart."
    log_info "Reboot scheduled in ${delay}s so this helper action can finish safely."
    (
        sleep "$delay"
        sync
        reboot
    ) >/dev/null 2>&1 &
    return 0
}

restart_klipper() {
    if is_k2pro_cfs_stack; then
        if [ "$1" != "force" ]; then
            echo "Creality K2 Pro Combo/CFS detected."
            echo "An isolated Klipper restart can break the vendor motor_control ready callback."
            printf "Schedule a safe full Linux reboot instead? [y/n]: "
            read confirm
            [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
        fi
        schedule_k2pro_reboot
        return $?
    fi

    if [ "$1" != "force" ]; then
        printf "Restart Klipper? [y/n]: "
        read confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    fi
    log_info "Restarting Klipper..."
    [ -x /etc/rc.d/S55klipper ] && /etc/rc.d/S55klipper restart || { log_error "S55klipper not found"; return 1; }
    sleep 3
    if pgrep -f "klippy.py" > /dev/null; then
        log_success "Klipper restarted successfully."
        return 0
    else
        log_error "Klipper failed to restart. Check $LOGS_DIR/klippy.log"
        return 1
    fi
}

restart_moonraker() {
    if [ "$1" != "force" ]; then
        printf "Restart Moonraker? [y/n]: "
        read confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    fi
    log_info "Restarting Moonraker..."
    # Kill ALL running moonraker instances (stock + helper script)
    for pid in $(ps aux | grep moonraker.py | grep -v grep | awk '{print $1}'); do
        kill "$pid" 2>/dev/null
    done
    sleep 2
    if [ -x /etc/init.d/moonraker ]; then
        /etc/init.d/moonraker start || return 1
    elif [ -x /etc/rc.d/S56moonraker ]; then
        /etc/rc.d/S56moonraker restart || /etc/rc.d/S56moonraker start || return 1
    else
        log_error "moonraker init script not found"
        return 1
    fi
    sleep 3
    if pgrep -f "moonraker.py" > /dev/null; then
        log_success "Moonraker restarted successfully."
        return 0
    else
        log_error "Moonraker failed to restart. Check $LOGS_DIR/moonraker.log"
        return 1
    fi
}

restart_nginx() {
    if [ "$1" != "force" ]; then
        printf "Restart Nginx? [y/n]: "
        read confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    fi
    log_info "Restarting Nginx..."
    [ -x /etc/rc.d/S80nginx ] && /etc/rc.d/S80nginx restart || { log_error "S80nginx not found"; return 1; }
    sleep 2
    if pgrep -f "nginx" > /dev/null; then
        log_success "Nginx restarted successfully."
        return 0
    else
        log_error "Nginx failed to restart."
        return 1
    fi
}

restart_camera() {
    log_info "Restarting helper camera bridge..."
    if [ -f /mnt/UDISK/helper-script/go2rtc ] && [ ! -x /mnt/UDISK/helper-script/go2rtc ]; then
        chmod +x /mnt/UDISK/helper-script/go2rtc 2>/dev/null || {
            log_error "go2rtc exists but could not be made executable"
            return 1
        }
        log_info "Restored executable bit on go2rtc."
    fi
    if [ -x /etc/rc.d/S99camera ]; then
        /etc/rc.d/S99camera restart || return 1
    elif [ -x /etc/init.d/S99camera ]; then
        /etc/init.d/S99camera restart || return 1
    else
        log_warn "S99camera not found; falling back to stock WebRTC service."
        [ -x /etc/rc.d/S97webrtc ] && /etc/rc.d/S97webrtc restart || { log_error "No camera service found"; return 1; }
    fi
    sleep 2
    log_success "Camera bridge restarted."
}

# ── Feature tracking ──────────────────────────────────────────────────────────

mark_installed() {
    local feature="$1"
    touch "$INSTALLED_FILE" 2>/dev/null
    if ! grep -q "^$feature$" "$INSTALLED_FILE" 2>/dev/null; then
        echo "$feature" >> "$INSTALLED_FILE"
    fi
}

mark_removed() {
    local feature="$1"
    if [ -f "$INSTALLED_FILE" ]; then
        tmp_file="${INSTALLED_FILE}.tmp.$$"
        grep -Fxv "$feature" "$INSTALLED_FILE" > "$tmp_file" 2>/dev/null || true
        mv "$tmp_file" "$INSTALLED_FILE"
    fi
}

is_installed() {
    local feature="$1"
    [ -f "$INSTALLED_FILE" ] && grep -q "^$feature$" "$INSTALLED_FILE"
}

show_installed() {
    echo ""
    echo "Installed features:"
    if [ -f "$INSTALLED_FILE" ] && [ -s "$INSTALLED_FILE" ]; then
        while IFS= read -r line; do
            printf "%b\n" "  ${GREEN}✓${NC} $line"
        done < "$INSTALLED_FILE"
    else
        echo "  None installed yet."
    fi
    echo ""
}

installed_flag() {
    local feature="$1"
    is_installed "$feature" && echo "yes" || echo "no"
}

detect_path() {
    local path="$1"
    [ -e "$path" ] && echo "yes" || echo "no"
}

detect_grep() {
    local pattern="$1"
    local path="$2"
    grep -qs "$pattern" "$path" 2>/dev/null && echo "yes" || echo "no"
}

print_save_config_state() {
    local api body tmp_json
    api="http://127.0.0.1:7125/printer/objects/query?configfile"
    if command -v curl >/dev/null 2>&1; then
        body="$(curl -fsS --max-time 4 "$api" 2>/dev/null || true)"
    elif [ -x /opt/bin/curl ]; then
        body="$(/opt/bin/curl -fsS --max-time 4 "$api" 2>/dev/null || true)"
    else
        echo "  [INFO] SAVE_CONFIG state not checked: curl not available."
        return 0
    fi

    if [ -z "$body" ]; then
        echo "  [INFO] SAVE_CONFIG state not checked: Moonraker API did not answer."
        return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        tmp_json="/tmp/helper_configfile_state.$$"
        printf '%s' "$body" > "$tmp_json" 2>/dev/null || tmp_json=""
        if [ -n "$tmp_json" ] && [ -s "$tmp_json" ]; then
            python3 - "$tmp_json" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        data = json.load(handle)
    cfg = data.get("result", {}).get("status", {}).get("configfile", {})
    pending = bool(cfg.get("save_config_pending"))
    items = cfg.get("save_config_pending_items") or {}
    keys = list(items.keys())
except Exception as exc:
    print("  [INFO] SAVE_CONFIG state parse failed: %s" % exc)
    sys.exit(0)

if not pending:
    print("  [OK]   SAVE_CONFIG pending: no.")
elif any(key.startswith("bed_mesh") for key in keys):
    print("  [WARN] SAVE_CONFIG pending includes bed_mesh: %s" % ",".join(keys))
    print("         Do not press SAVE_CONFIG after KAMP adaptive tests; restart Klipper/FIRMWARE_RESTART to discard the temporary mesh.")
elif keys == ["auto_addr"]:
    print("  [INFO] SAVE_CONFIG pending only looks like Creality CFS auto_addr; do not save just for this.")
else:
    print("  [WARN] SAVE_CONFIG pending: %s" % (",".join(keys) or "yes"))
PY
            rm -f "$tmp_json" 2>/dev/null
            return 0
        fi
    fi

    if echo "$body" | grep -q '"save_config_pending"[[:space:]]*:[[:space:]]*false'; then
        echo "  [OK]   SAVE_CONFIG pending: no."
        return 0
    fi
    if echo "$body" | grep -q '"save_config_pending"[[:space:]]*:[[:space:]]*true'; then
        if echo "$body" | grep -q '"save_config_pending_items"[^{]*{[^}]*"auto_addr"'; then
            echo "  [INFO] SAVE_CONFIG pending only looks like Creality CFS auto_addr; do not save just for this."
        else
            echo "  [WARN] SAVE_CONFIG pending: yes. Install/use python3 for exact item classification before saving."
        fi
    fi
}

print_status_row() {
    local label="$1"
    local feature="$2"
    local evidence="$3"
    local note="$4"
    local marked
    marked="$(installed_flag "$feature")"

    if [ "$marked" = "yes" ] && [ "$evidence" = "yes" ]; then
        printf "  [OK]   %-31s marked=yes detected=yes  %s\n" "$label" "$note"
    elif [ "$marked" = "yes" ]; then
        printf "  [WARN] %-31s marked=yes detected=no   %s\n" "$label" "$note"
    elif [ "$evidence" = "yes" ]; then
        printf "  [INFO] %-31s marked=no  detected=yes  %s\n" "$label" "$note"
    else
        printf "  [--]   %-31s marked=no  detected=no   %s\n" "$label" "$note"
    fi
}

installed_status() {
    local model board fw helper_line moonraker_pid klipper_pid
    model="$(/usr/bin/get_sn_mac.sh model 2>/dev/null)"
    board="$(/usr/bin/get_sn_mac.sh board 2>/dev/null)"
    fw="$(fw_printenv version 2>/dev/null | cut -d= -f2)"
    helper_line="$(sed -n '2p' "$SCRIPT_DIR/helper.sh" 2>/dev/null)"
    moonraker_pid="$(pgrep -f "moonraker.py" 2>/dev/null | tr '\n' ' ')"
    klipper_pid="$(pgrep -f "klippy.py" 2>/dev/null | tr '\n' ' ')"

    echo ""
    echo "Helper installation overview"
    echo "============================"
    echo "Helper: ${helper_line:-unknown}"
    echo "Printer: model=${model:-unknown} board=${board:-unknown} firmware=${fw:-unknown}"
    echo "Install marker: $INSTALLED_FILE"
    echo "Klipper PID(s): ${klipper_pid:-not running}"
    echo "Moonraker PID(s): ${moonraker_pid:-not running}"
    echo ""

    echo "Tracked helper modules"
    echo "----------------------"
    print_status_row "Moonraker extensions" "moonraker_extensions" "$(detect_grep "CONF=/mnt/UDISK/printer_data/config/moonraker.conf" "/etc/init.d/moonraker")" "Moonraker config wrapper/start patch"
    print_status_row "Fluidd updated" "fluidd_updated" "$(detect_path "/usr/share/fluidd")" "web UI, usually :4408"
    print_status_row "Mainsail" "mainsail" "$(detect_path "/usr/share/mainsail")" "web UI, usually :4409"
    camera_evidence="no"
    { [ -e /etc/rc.d/S99camera ] || [ -e /etc/init.d/S99camera ]; } && camera_evidence="yes"
    print_status_row "Camera support" "camera_support" "$camera_evidence" "go2rtc/WebRTC bridge"
    print_status_row "Fans control macros" "fans_control_macros" "$(detect_path "$CONFIG_DIR/fans_control.cfg")" "K2 Pro fan macro cfg"
    print_status_row "Useful macros" "useful_macros" "$(detect_path "$CONFIG_DIR/useful_macros.cfg")" "CFS-safe utility macros"
    print_status_row "Improved shapers" "improved_shapers" "$(detect_path "$CONFIG_DIR/shapers_calibration.cfg")" "input shaper helpers"
    if [ -d "$CONFIG_DIR/KAMP" ] || grep -qs "KAMP/KAMP_Settings.cfg" "$CONFIG_DIR/printer.cfg" 2>/dev/null; then
        print_status_row "KAMP-K2 adaptive mesh" "kamp" "yes" "adaptive mesh tested on live K2 Pro"
    else
        print_status_row "KAMP-K2 adaptive mesh" "kamp" "no" "adaptive mesh helper"
    fi
    timelapse_evidence="no"
    { [ -e /etc/rc.d/S99timelapse_recover ] || [ -e /etc/init.d/S99timelapse_recover ]; } && timelapse_evidence="yes"
    print_status_row "Creality timelapse recover" "creality_timelapse_recover" "$timelapse_evidence" "stock timelapse MP4 recover"
    spoolman_evidence="no"
    spoolman_note="CFS/Spoolman helper service"
    if { [ -x /etc/rc.d/S99spoolman_cfs_sync ] || [ -x /etc/init.d/S99spoolman_cfs_sync ]; } && [ -x "$SCRIPT_DIR/spoolman_cfs_sync.py" ]; then
        spoolman_evidence="yes"
        if [ -f "$SCRIPT_DIR/spoolman_cfs_map.json" ]; then
            spoolman_note="service/worker present; active map exists"
        elif [ -f "$SCRIPT_DIR/spoolman_cfs_map.example.json" ]; then
            spoolman_note="service/worker present; no active map overwritten, example exists"
        else
            spoolman_note="service/worker present; active slot map missing"
        fi
    fi
    print_status_row "Spoolman CFS sync" "spoolman_cfs_sync" "$spoolman_evidence" "$spoolman_note"
    cfs_safe_evidence="no"
    if { [ -x /etc/rc.d/S97cfs_safe_monitor ] || [ -x /etc/init.d/S97cfs_safe_monitor ]; } && [ -x "$SCRIPT_DIR/scripts/cfs_safe_tools.py" ]; then
        cfs_safe_evidence="yes"
    fi
    print_status_row "CFS Safe Tools" "cfs_safe_tools" "$cfs_safe_evidence" "passive CFS diagnostics and event statistics"
    status_hub_evidence="no"
    if [ -L /usr/share/fluidd/k2-status ] && [ -L /usr/share/mainsail/k2-status ]; then
        status_hub_evidence="yes"
    fi
    print_status_row "K2 compact status page" "k2_status_hub" "$status_hub_evidence" "shared read-only Fluidd/Mainsail/Helix/K2Dash view"
    gc_evidence="no"
    if [ -f "/usr/share/klipper/klippy/extras/garbage_collection.py" ] && \
       [ -f "$CONFIG_DIR/k2pro_garbage_collection.cfg" ] && \
       grep -Fqs '[include k2pro_garbage_collection.cfg]' "$CONFIG_DIR/printer.cfg" 2>/dev/null; then
        gc_evidence="yes"
    fi
    print_status_row "Klipper Garbage Collection" "klipper_gc" "$gc_evidence" "upstream GC optimization with K2-safe reboot"
    gcode_time_evidence="no"
    if [ -x "$SCRIPT_DIR/scripts/gcode_time_hybrid.sh" ] && \
       sh "$SCRIPT_DIR/scripts/gcode_time_hybrid.sh" status >/dev/null 2>&1; then
        gcode_time_evidence="yes"
    fi
    print_status_row "Factory G-Code Hybrid Times" "gcode_time_hybrid" "$gcode_time_evidence" "K2 Pro sample estimates survive the stock boot rsync"
    print_status_row "Entware" "entware" "$(detect_path "/opt/bin/opkg")" "package manager and tools"
    print_status_row "Git Backup local" "git_backup" "$(detect_path "$CONFIG_DIR/.git")" "local config history; remote optional"
    if [ -e /etc/init.d/octoeverywhere ] || [ -e /etc/rc.d/S99octoeverywhere ]; then
        print_status_row "OctoEverywhere" "octoeverywhere" "yes" "cloud remote access, explicit installer only"
    else
        print_status_row "OctoEverywhere" "octoeverywhere" "no" "cloud remote access, explicit installer only"
    fi
    print_status_row "Mobileraker helper" "mobileraker" "no" "phone app uses Moonraker directly; companion belongs on Raspi/Debian"
    print_status_row "Moonraker timelapse" "moonraker_timelapse" "$(detect_path "$CONFIG_DIR/timelapse.cfg")" "Moonraker timelapse plugin"
    if [ -f "$CONFIG_DIR/m600.cfg" ] || grep -qs "m600.cfg" "$CONFIG_DIR/printer.cfg" 2>/dev/null; then
        print_status_row "M600 manual change" "m600_support" "yes" "manual filament macro; only without CFS/Box"
    else
        print_status_row "M600 manual change" "m600_support" "no" "manual filament macro; only without CFS/Box"
    fi
    echo ""

    echo "Detected extra state"
    echo "--------------------"
    if [ -d "$CONFIG_DIR/KAMP" ] || grep -qs "KAMP/KAMP_Settings.cfg" "$CONFIG_DIR/printer.cfg" 2>/dev/null; then
        echo "  [INFO] KAMP-K2 detected: KAMP config or include is present."
    else
        echo "  [--]   KAMP-K2 not detected in active config."
    fi
    if [ -f "/usr/share/klipper/klippy/extras/restore_bed_mesh.py" ]; then
        echo "  [INFO] restore_bed_mesh.py present."
    fi
    if [ -x "/usr/bin/wget" ]; then
        echo "  [OK]   /usr/bin/wget present."
    else
        echo "  [WARN] /usr/bin/wget missing; timelapse/frame scripts may need helper fallback."
    fi
    if [ -x "/usr/bin/curl" ] || [ -x "/opt/bin/curl" ]; then
        echo "  [OK]   curl present."
    else
        echo "  [WARN] curl missing."
    fi
    if [ -f "$CONFIG_DIR/moonraker.conf" ]; then
        echo "  [OK]   Active moonraker.conf exists in printer_data/config."
    else
        echo "  [WARN] Active moonraker.conf missing from printer_data/config."
    fi
    print_save_config_state

    echo ""
    show_installed
}

# ── printer.cfg include management ───────────────────────────────────────────

# Add an [include filename.cfg] line to printer.cfg if not already present
add_include_to_printer_cfg() {
    local include_file="$1"
    local printer_cfg="$CONFIG_DIR/printer.cfg"
    local include_line="[include ${include_file}]"

    if grep -Fxq "$include_line" "$printer_cfg" 2>/dev/null; then
        log_info "[include ${include_file}] already present in printer.cfg"
        return 0
    fi

    # Insert after the last existing [include ...] line, or at top if none
    if grep -q "^\[include " "$printer_cfg"; then
        # Find line number of last include and insert after it
        last_include=$(grep -n "^\[include " "$printer_cfg" | tail -1 | cut -d: -f1)
        sed -i "${last_include}a ${include_line}" "$printer_cfg"
    else
        # No includes yet - add after the first comment block
        sed -i "1s/^/${include_line}\n/" "$printer_cfg"
    fi

    log_success "Added [include ${include_file}] to printer.cfg"
}

# Remove an [include filename.cfg] line from printer.cfg
remove_include_from_printer_cfg() {
    local include_file="$1"
    local printer_cfg="$CONFIG_DIR/printer.cfg"
    local include_line="[include ${include_file}]"

    if grep -Fxq "$include_line" "$printer_cfg" 2>/dev/null; then
        tmp_file="${printer_cfg}.tmp.$$"
        grep -Fxv "$include_line" "$printer_cfg" > "$tmp_file" 2>/dev/null || true
        mv "$tmp_file" "$printer_cfg"
        log_success "Removed [include ${include_file}] from printer.cfg"
    fi
}

# ── moonraker.conf management ─────────────────────────────────────────────────

MOONRAKER_CONF=$CONFIG_DIR/moonraker.conf
MOONRAKER_RC=/etc/init.d/moonraker
[ -f "$MOONRAKER_RC" ] || MOONRAKER_RC=/etc/rc.d/S56moonraker
MOONRAKER_RC_BAK=/mnt/UDISK/helper-script/.S56moonraker.orig
MOONRAKER_STOCK_CONF=/usr/share/moonraker/moonraker.conf

# Patch S56moonraker to use our config wrapper instead of the stock one
patch_moonraker_startup() {
    if [ ! -f "$MOONRAKER_RC" ]; then
        log_error "Moonraker startup script not found: $MOONRAKER_RC"
        return 1
    fi
    if grep -q "CONF=/mnt/UDISK/printer_data/config/moonraker.conf" "$MOONRAKER_RC" 2>/dev/null; then
        log_info "Moonraker startup already patched."
        return 0
    fi
    if ! grep -q "CONF=/usr/share/moonraker/moonraker.conf" "$MOONRAKER_RC" 2>/dev/null; then
        log_error "Expected stock CONF line not found in $MOONRAKER_RC. Not patching."
        return 1
    fi

    # Back up original with timestamp and keep .orig for removal compatibility
    ts=$(date +%Y%m%d_%H%M%S)
    cp "$MOONRAKER_RC" "${MOONRAKER_RC}.orig.$ts"
    [ ! -f "${MOONRAKER_RC}.orig" ] && cp "$MOONRAKER_RC" "${MOONRAKER_RC}.orig"
    log_success "Backed up original Moonraker startup to ${MOONRAKER_RC}.orig.$ts"

    sed -i "s|CONF=/usr/share/moonraker/moonraker.conf|CONF=/mnt/UDISK/printer_data/config/moonraker.conf|g" "$MOONRAKER_RC"
    log_success "Patched Moonraker startup to use /mnt/UDISK/printer_data/config/moonraker.conf"
}

# Restore the original CONF= line
unpatch_moonraker_startup() {
    if [ -f "${MOONRAKER_RC}.orig" ]; then
        cp "${MOONRAKER_RC}.orig" "$MOONRAKER_RC"
        log_success "Restored original Moonraker startup."
        rm -f "${MOONRAKER_RC}.orig"
    else
        # Restore manually if backup is missing
        sed -i "s|CONF=/mnt/UDISK/printer_data/config/moonraker.conf|CONF=/usr/share/moonraker/moonraker.conf|g" "$MOONRAKER_RC"
        log_success "Restored Moonraker CONF to stock path."
    fi
}

# Add a section to our moonraker.conf (idempotent)
add_moonraker_section() {
    local section_name="$1"
    local section_content="$2"

    if grep -q "^\[${section_name}" "$MOONRAKER_CONF" 2>/dev/null; then
        log_info "[$section_name] already present in moonraker.conf"
        return 0
    fi

    echo "" >> "$MOONRAKER_CONF"
    echo "$section_content" >> "$MOONRAKER_CONF"
    log_success "Added [$section_name] to moonraker.conf"
}

# Remove a section from our moonraker.conf
remove_moonraker_section() {
    local section_name="$1"
    if [ ! -f "$MOONRAKER_CONF" ]; then return 0; fi

    # Remove exactly one INI section, preserving comments and following sections.
    python3 - "$MOONRAKER_CONF" "$section_name" << 'PYEOF'
import sys
path, section = sys.argv[1], sys.argv[2]
with open(path) as f:
    lines = f.readlines()

target = "[" + section + "]"
out = []
skip = False
removed = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        if stripped == target:
            skip = True
            removed = True
            continue
        skip = False
    if not skip:
        out.append(line)

with open(path, 'w') as f:
    f.writelines(out)
if not removed:
    sys.exit(2)
PYEOF
    rc=$?
    if [ $rc -eq 0 ]; then
        log_success "Removed [$section_name] from moonraker.conf"
    elif [ $rc -eq 2 ]; then
        log_info "[$section_name] not present in moonraker.conf"
    else
        log_error "Failed to remove [$section_name] from moonraker.conf"
        return 1
    fi
}

# Enable Moonraker metadata settings in the active stock config. Creality's
# bundled config is included by the UDISK wrapper, so these are the settings
# Fluidd and Mainsail actually inherit for G-code metadata extraction.
ensure_moonraker_gcode_queue() {
    local target="$MOONRAKER_STOCK_CONF"
    local backup_dir="$CONFIG_DIR/../backups/k2pro_helper/moonraker_queue"
    local backup_file=""
    local changed=0
    local ts

    if [ ! -f "$target" ]; then
        log_error "Moonraker stock config not found: $target"
        return 1
    fi

    if ! grep -Eq "^[[:space:]]*queue_gcode_uploads:[[:space:]]*(True|False)[[:space:]]*$" "$target" 2>/dev/null; then
        log_error "queue_gcode_uploads setting not found in $target; not patching blindly"
        return 1
    fi
    if ! grep -Eq "^[[:space:]]*enable_object_processing:[[:space:]]*(True|False)[[:space:]]*$" "$target" 2>/dev/null; then
        log_error "enable_object_processing setting not found in $target; not patching blindly"
        return 1
    fi

    mkdir -p "$backup_dir" || {
        log_error "Could not create backup directory: $backup_dir"
        return 1
    }
    ts=$(date +%Y%m%d_%H%M%S)
    backup_file="$backup_dir/moonraker.conf.before_metadata_flags_$ts"
    cp "$target" "$backup_file" || {
        log_error "Could not back up $target"
        return 1
    }

    if grep -Eq "^[[:space:]]*queue_gcode_uploads:[[:space:]]*False[[:space:]]*$" "$target" 2>/dev/null; then
        sed -i "s/^\([[:space:]]*queue_gcode_uploads:[[:space:]]*\)False[[:space:]]*$/\1True/" "$target"
        changed=1
    fi
    if grep -Eq "^[[:space:]]*enable_object_processing:[[:space:]]*False[[:space:]]*$" "$target" 2>/dev/null; then
        sed -i "s/^\([[:space:]]*enable_object_processing:[[:space:]]*\)False[[:space:]]*$/\1True/" "$target"
        changed=1
    fi

    if grep -Eq "^[[:space:]]*queue_gcode_uploads:[[:space:]]*True[[:space:]]*$" "$target" 2>/dev/null; then
        log_success "Moonraker queue_gcode_uploads enabled in $target"
    else
        log_error "queue_gcode_uploads patch did not verify in $target"
        return 1
    fi

    if grep -Eq "^[[:space:]]*enable_object_processing:[[:space:]]*True[[:space:]]*$" "$target" 2>/dev/null; then
        log_success "Moonraker enable_object_processing enabled in $target"
    else
        log_error "enable_object_processing patch did not verify in $target"
        return 1
    fi

    [ "$changed" -eq 1 ] && log_info "Backup: $backup_file" || log_info "Moonraker metadata flags were already enabled."
    return 0
}

# ── nginx management ──────────────────────────────────────────────────────────

NGINX_CONF=/etc/nginx/nginx.conf
NGINX_CONF_BAK=/mnt/UDISK/helper-script/.nginx.conf.bak

backup_nginx_conf() {
    if [ ! -f "$NGINX_CONF" ]; then
        log_warn "nginx.conf not found at $NGINX_CONF; skipping nginx backup"
        return 0
    fi
    if [ ! -f "$NGINX_CONF_BAK" ]; then
        cp "$NGINX_CONF" "$NGINX_CONF_BAK" && log_success "Backed up nginx.conf to $NGINX_CONF_BAK" || log_warn "Could not back up nginx.conf"
    fi
}

restore_nginx_conf() {
    if [ -f "$NGINX_CONF_BAK" ]; then
        cp "$NGINX_CONF_BAK" "$NGINX_CONF"
        log_success "Restored nginx.conf from backup."
        rm -f "$NGINX_CONF_BAK"
        restart_nginx
    else
        log_warn "No nginx.conf backup found."
    fi
}

# ── Entry point ───────────────────────────────────────────────────────────────
# system.sh is sourced by many feature scripts. Only dispatch CLI commands when
# this file is executed directly; otherwise arguments like "status" would leak
# from the caller and trigger the full helper overview unexpectedly.
if [ "$(basename "$0")" = "system.sh" ]; then
    case "$1" in
        restart_klipper)   restart_klipper "$2" ;;
        restart_moonraker) restart_moonraker "$2" ;;
        restart_nginx)     restart_nginx "$2" ;;
        restart_camera)    restart_camera ;;
        show_installed)    show_installed ;;
        installed_status|status|show_status) installed_status ;;
        fix_moonraker_queue|ensure_moonraker_gcode_queue) ensure_moonraker_gcode_queue ;;
    esac
fi
