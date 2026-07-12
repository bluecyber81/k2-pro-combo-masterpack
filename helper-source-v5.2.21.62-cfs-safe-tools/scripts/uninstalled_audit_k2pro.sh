#!/bin/sh
# uninstalled_audit_k2pro.sh - read-only check for modules intentionally not installed
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

result_row() {
    printf "%-24s %-14s %s\n" "$1" "$2" "$3"
}

exists_or_no() {
    [ -e "$1" ] && echo "yes" || echo "no"
}

marked_or_no() {
    is_installed "$1" && echo "yes" || echo "no"
}

echo ""
echo "K2 Pro Combo uninstalled-module audit"
echo "Safety: read-only only. This does not install, flash, move, heat or restart."
echo ""

printf "%-24s %-14s %s\n" "Module" "Decision" "Reason"
printf "%-24s %-14s %s\n" "------------------------" "--------------" "----------------------------------------"

if is_installed "creality_timelapse_recover" && [ -x /etc/rc.d/S99timelapse_recover ]; then
    tl_decision="keep-off"
    tl_note="Creality Timelapse Recover is installed and matches the stock Creality workflow"
else
    tl_decision="optional"
    tl_note="only useful for Moonraker slicer TIMELAPSE_TAKE_FRAME/TIMELAPSE_RENDER workflow"
fi
[ -x /usr/bin/ffmpeg ] && tl_note="$tl_note; ffmpeg=yes" || tl_note="$tl_note; ffmpeg=no"
result_row "Moonraker Timelapse" "$tl_decision" "$tl_note"

if [ -f "$CONFIG_DIR/m600.cfg" ] || grep -qs "m600.cfg" "$CONFIG_DIR/printer.cfg" 2>/dev/null; then
    result_row "M600" "installed" "manual filament macro is active; verify no CFS/Box is used"
else
    result_row "M600" "keep-off" "correct: only use M600 on printers without CFS/Box"
fi

if [ -f "$CONFIG_DIR/z_offset_macros.cfg" ] || grep -qs "z_offset_macros.cfg" "$CONFIG_DIR/printer.cfg" 2>/dev/null; then
    result_row "Z-Offset Macros" "installed" "review before SAVE_CONFIG"
else
    result_row "Z-Offset Macros" "blocked" "not better for normal K2 Pro use; wrong persisted offset can damage bed/nozzle"
fi

if [ -f /etc/init.d/S99helixscreen ] || [ -d /opt/helixscreen ] || is_installed "helixscreen"; then
    result_row "HelixScreen" "installed" "HelixScreen traces present; inspect status before changing display stack"
else
    result_row "HelixScreen" "test-only" "upstream supports K2 Pro, but stock display/CFS/AI/camera workflow is working here"
fi

result_row "OctoEverywhere" "external" "official cloud installer is available, but requires explicit confirmation/account setup"
result_row "Mobileraker" "info" "local app access needs no printer-side install; Companion is better on Raspberry Pi/Debian"
if is_installed "git_backup" && [ -d "$CONFIG_DIR/.git" ]; then
    result_row "Git Backup" "installed" "local config Git history is active"
elif [ -d "$CONFIG_DIR/.git" ]; then
    result_row "Git Backup" "detected" "Git history exists; helper marker can be repaired with Git Backup install"
else
    result_row "Git Backup" "available" "local config snapshots are implemented and safe to enable after backup"
fi

echo ""
echo "Detected state"
echo "--------------"
echo "moonraker_timelapse_marked=$(marked_or_no moonraker_timelapse)"
echo "timelapse_cfg=$(exists_or_no "$CONFIG_DIR/timelapse.cfg")"
echo "m600_marked=$(marked_or_no m600_support)"
echo "m600_cfg=$(exists_or_no "$CONFIG_DIR/m600.cfg")"
echo "z_offset_marked=$(marked_or_no z_offset_macros)"
echo "z_offset_cfg=$(exists_or_no "$CONFIG_DIR/z_offset_macros.cfg")"
echo "helixscreen_marked=$(marked_or_no helixscreen)"
echo "helixscreen_service=$(exists_or_no /etc/init.d/S99helixscreen)"
echo "helixscreen_dir=$(exists_or_no /opt/helixscreen)"
echo "stock_display_server_running=$(pidof display-server >/dev/null 2>&1 && echo yes || echo no)"
echo "creality_timelapse_recover_marked=$(marked_or_no creality_timelapse_recover)"
echo "git_backup_marked=$(marked_or_no git_backup)"
echo "git_backup_repo=$(exists_or_no "$CONFIG_DIR/.git")"
echo ""
echo "Recommendation: keep these modules off by default. The current installed set is the better K2 Pro Combo baseline. Use --helixscreen-audit before any HelixScreen experiment."
