#!/bin/sh
# menu_audit_k2pro.sh - non-destructive menu suitability check for K2 Pro Combo
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

has_cfg() {
    grep -Rqs "$1" "$CONFIG_DIR"/*.cfg 2>/dev/null
}

feature_state() {
    feature="$1"
    if [ -n "$feature" ] && is_installed "$feature"; then
        printf "installed"
    else
        printf "available"
    fi
}

row() {
    no="$1"
    state="$2"
    title="$3"
    feature="$4"
    note="$5"
    printf "%-3s %-13s %-26s %-11s %s\n" "$no" "$state" "$title" "$(feature_state "$feature")" "$note"
}

MODEL="$(/usr/bin/get_sn_mac.sh model 2>/dev/null)"
BOARD="$(/usr/bin/get_sn_mac.sh board 2>/dev/null)"
FW_VERSION="$(fw_printenv version 2>/dev/null | cut -d= -f2)"

echo ""
echo "K2 Pro Combo helper menu suitability audit"
echo "Model=${MODEL:-unknown} Board=${BOARD:-unknown} Firmware=${FW_VERSION:-unknown}"
echo "This is read-only. No router/Fritzbox/WAN settings are changed."
echo ""

if [ "$MODEL" = "F012" ] && [ "$BOARD" = "CR0CN200400C10" ]; then
    echo "[OK] Printer identity matches K2 Pro Combo."
else
    echo "[WARN] Printer identity does not fully match expected K2 Pro Combo values."
fi

if grep -RqsE "Printer_size:[[:space:]]*300[\*x]300[\*x]300" "$CONFIG_DIR/printer.cfg" "$CONFIG_DIR/printer_params.cfg" 2>/dev/null; then
    echo "[OK] 300x300x300 size marker found."
else
    echo "[WARN] 300x300x300 size marker not found in printer.cfg/printer_params.cfg."
fi

if has_cfg "^\[box\]" && has_cfg "BOX_LOAD_MATERIAL"; then
    echo "[WARN] CFS/Box direct load macros exist; use display/official CFS workflow, not direct BOX_LOAD_MATERIAL tests."
fi

if has_cfg "^\[output_pin fan0\]" && has_cfg "^\[output_pin fan2\]"; then
    fan_note="fan0/fan2 present"
else
    fan_note="fan pins differ; macros fall back/skip"
fi

if has_cfg "^\[resonance_tester\]"; then
    shaper_note="resonance_tester present"
else
    shaper_note="requires existing resonance_tester"
fi

if has_cfg "^\[heater_generic chamber_heater\]"; then
    chamber_note="chamber heater present"
else
    chamber_note="chamber macros skip if missing"
fi

printf "%-3s %-13s %-26s %-11s %s\n" "No" "Fit" "Menu item" "State" "Note"
printf "%-3s %-13s %-26s %-11s %s\n" "--" "-------------" "--------------------------" "-----------" "------------------------------"
row 1  "OK"        "Preflight report"       ""                         "read-only"
row 2  "OK"        "Backup"                 ""                         "recommended before installs"
row 3  "OK"        "Installed features"     ""                         "read-only"
row 4  "CAUTION"   "Moonraker Extensions"   "moonraker_extensions"     "local update_manager/metadata basis; do not update Creality core blindly"
row 5  "OK"        "Fans Control"           "fans_control_macros"      "$fan_note"
row 6  "CAUTION"   "Useful Macros"          "useful_macros"            "moves/heats; SAVE_CONFIG blocks CFS auto_addr; $chamber_note"
row 7  "SPECIAL"   "M600 manual change"     "m600_support"             "blocked when CFS/Box is detected; only for non-CFS manual printers"
row 8  "CAUTION"   "Improved Shapers"       "improved_shapers"         "$shaper_note; SAVE_CONFIG blocks CFS auto_addr"
row 9  "OK"        "Fluidd"                 "fluidd_updated"           "local port 4408"
row 10 "OK"        "Mainsail"               "mainsail"                 "local port 4409"
row 11 "CAUTION"   "Moonraker Timelapse"    "moonraker_timelapse"      "optional; Creality Timelapse Recover is preferred on this printer"
row 12 "OK"        "Camera Support"         "camera_support"           "local go2rtc bridge/proxy"
row 13 "EXTERNAL" "OctoEverywhere"          "octoeverywhere"           "official cloud installer only after explicit confirmation"
row 14 "INFO"     "Mobileraker"             "mobileraker"              "phone app uses Moonraker directly; Companion recommended on Raspi/Debian"
row 15 "CAUTION"   "Entware"                "entware"                  "internet/system package manager; only if explicitly wanted"
row 16 "OK"        "Git Backup local"       "git_backup"               "local config Git history; remote push optional/manual"
row 17 "BLOCKED"   "Save Z-Offset"          "z_offset_macros"          "expert-only; SAVE_CONFIG blocks CFS auto_addr"
row 18 "OK"        "KAMP-K2 adaptive mesh"  "kamp"                     "installed/tested on this printer; keep SAVE_CONFIG warning"
row 19 "TEST-ONLY" "HelixScreen"            "helixscreen"              "upstream K2 Pro support exists; stock display/CFS/AI must be retested"
row 20 "OK"        "Restore/remove menu"     ""                         "restore backup is visible before remove actions"
row 21 "OK"        "Restore backup"         ""                         "interactive restore; no longer hidden behind an unused handler"
row 22 "OK"        "Restart Klipper"        ""                         "service restart"
row 23 "OK"        "Restart Moonraker"      ""                         "service restart"
row 24 "OK"        "Restart Nginx"          ""                         "local web service restart"
row 25 "OK"        "View Klipper log"       ""                         "read-only"
row 26 "OK"        "View Moonraker log"     ""                         "read-only"
row 27 "OK"        "Expert status"          ""                         "read-only"
row 28 "OK"        "Camera health"          ""                         "read-only checks"
row 29 "OK"        "CFS/BOX diagnosis"      ""                         "read-only checks"
row 30 "OK"        "Full helper health"     ""                         "read-only checks"
row 31 "OK"        "Restart camera bridge"  ""                         "local helper camera restart"
row 32 "OK"        "Menu audit"             ""                         "this report"
row 33 "OK"        "Fluidd/Mainsail health" ""                         "read-only UI/API checks"
row 34 "OK"        "Firmware health"        ""                         "read-only firmware summary"
row 35 "OK"        "Moonraker queue fix"    ""                         "backs up config; fixes G-code preview metadata race"
row 36 "OK"        "CFS safety scan"        ""                         "read-only config/G-code/log scan"
row 37 "OK"        "Timelapse Recover"      "creality_timelapse_recover" "renders Creality main_output.h264 to stock delay_image MP4"
row 38 "OK"        "Uninstalled audit"      ""                         "read-only check for modules intentionally kept off"
row 39 "OK"        "HelixScreen audit"      ""                         "read-only stock-display/Helix compatibility check"
row 40 "OK"        "Dependency audit"       ""                         "read-only command/service/port/dependency matrix"
row 41 "OK"        "CFS Material DB Guard"  "cfs_db_guard"             "keeps eSUN/Sovol custom CFS profiles durable after boot"
row 42 "OK"        "CFS DB repair"          ""                         "backup-first JSON repair, no CFS/BOX commands"
row 43 "OK"        "CFS DB guard status"    ""                         "read-only guard check"
row 44 "OK"        "CFS protocol/slot report" ""                       "read-only bus model, slot and DB mapping report"
row 45 "OK"        "Deep file/script audit" ""                         "read-only scripts/configs/services/logs audit"
row 46 "OK"        "Timelapse Recover status" ""                       "status is visible in Status menu"
row 47 "OK"        "Entware status"         "entware"                  "status is visible in Status menu"
row 48 "OK"        "Nozzle AI USB diagnose" ""                         "read-only UVC/BIND/hotplug/video-node report; does not force camera on"

echo ""
echo "Recommended first run: Preflight -> Backup -> Installed overview -> Full health -> CFS/BOX -> Camera -> Frontends -> Firmware -> Menu audit -> Dependency audit -> Deep file/script audit."
echo "Recommended for this printer now: keep Moonraker/Fluidd/Mainsail/Camera helper fixes, keep tested KAMP-K2, keep CFS Material DB Guard, use Creality Timelapse Recover for stock time-lapse MP4 creation, use CFS/display for material handling, keep local Git Backup for config history, scan CFS-related G-code before printing, use the CFS protocol/slot report after firmware resets, keep Nozzle AI camera on Creality on-demand control and diagnose USB/UVC only when AI fails, keep Z-Offset locked, keep Moonraker Timelapse optional, and treat HelixScreen as a separate reversible display experiment only."
