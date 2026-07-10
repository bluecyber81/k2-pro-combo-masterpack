#!/bin/sh
# Collect a read-only status snapshot plus backups for the user's K2 Pro Combo.
# No restore, no flash, no print start, and no CFS load/unload commands are run here.

STAMP="${1:-$(date +%Y%m%d_%H%M%S)}"
ROOT_DIR="/mnt/UDISK/printer_data/backups/codex/k2pro_masterpack_${STAMP}"
REMOTE_DIR="$ROOT_DIR/remote_files"
REPORT_DIR="$ROOT_DIR/reports"
HELPER_DIR="/mnt/UDISK/helper-script"

mkdir -p "$REMOTE_DIR" "$REPORT_DIR"

SUMMARY="$ROOT_DIR/K2PRO_MASTERPACK_LIVE_SUMMARY_${STAMP}.txt"
SHA_FILE="$ROOT_DIR/SHA256SUMS.txt"

log() {
    printf '%s\n' "$*" | tee -a "$SUMMARY"
}

capture() {
    name="$1"
    shift
    out="$REPORT_DIR/${name}_${STAMP}.txt"
    {
        printf '### %s\n' "$name"
        printf '### command:'
        printf ' %s' "$@"
        printf '\n\n'
        "$@"
    } > "$out" 2>&1
    rc=$?
    log "report:$name:$out:rc=$rc"
    return 0
}

run_helper_report() {
    name="$1"
    arg="$2"
    if [ -x "$HELPER_DIR/helper.sh" ] || [ -f "$HELPER_DIR/helper.sh" ]; then
        capture "$name" sh "$HELPER_DIR/helper.sh" "$arg"
    else
        log "skip:$name:helper.sh not found"
    fi
}

: > "$SUMMARY"
log "K2 Pro Combo live masterpack snapshot"
log "stamp:$STAMP"
log "root_dir:$ROOT_DIR"
log "date:$(date)"
log "hostname:$(hostname 2>/dev/null)"
log "id:$(id 2>/dev/null)"
log "uname:$(uname -a 2>/dev/null)"
log "firmware:$(fw_printenv version 2>/dev/null | head -n 1)"
log "helper_header:$(head -n 2 "$HELPER_DIR/helper.sh" 2>/dev/null | tail -n 1)"
log ""

capture system_identity sh -c 'date; hostname; id; uname -a; fw_printenv version 2>/dev/null || true; fw_printenv HW_VERSION 2>/dev/null || true; df -h'
capture helper_listing sh -c 'ls -la /mnt/UDISK/helper-script 2>/dev/null; echo; test -f /mnt/UDISK/helper-script/.installed && cat /mnt/UDISK/helper-script/.installed || true'
capture printer_config_listing sh -c 'find /mnt/UDISK/printer_data/config -maxdepth 2 -type f 2>/dev/null | sort'

run_helper_report helper_status --status
run_helper_report helper_preflight --preflight
run_helper_report helper_health --health
run_helper_report helper_health_camera --health-camera
run_helper_report helper_health_frontends --health-frontends
run_helper_report helper_health_cfs --health-cfs
run_helper_report helper_health_firmware --health-firmware
run_helper_report helper_nozzle_camera_diagnose --nozzle-camera-diagnose
run_helper_report helper_dependency_audit --dependency-audit
run_helper_report helper_menu_audit --menu-audit
run_helper_report helper_uninstalled_audit --uninstalled-audit
run_helper_report helper_deep_file_audit --deep-file-audit
run_helper_report helper_spoolman_cfs_status --spoolman-cfs-status
run_helper_report helper_cfs_protocol_report --cfs-protocol-report
run_helper_report helper_cfs_db_guard_status --cfs-db-guard-status
run_helper_report helper_timelapse_recover_status --timelapse-recover-status
run_helper_report helper_entware_status --entware-status
run_helper_report helper_git_backup_status --git-backup-status

capture service_process_status sh -c '
    date
    /etc/init.d/moonraker status 2>/dev/null || true
    /etc/init.d/go2rtc status 2>/dev/null || true
    /etc/init.d/S99spoolman_cfs_sync status 2>/dev/null || true
    ps w | grep -E "[m]oonraker|[k]lippy|[g]o2rtc|[s]poolman_cfs_sync|[c]reality_timelapse" || true
    netstat -lntp 2>/dev/null || true
'

if [ -d "$HELPER_DIR" ]; then
    HELPER_TAR="$REMOTE_DIR/helper-script-live_${STAMP}.tar.gz"
    tar -czf "$HELPER_TAR" -C /mnt/UDISK helper-script
    log "helper_snapshot:$HELPER_TAR:rc=$?"
fi

if [ -f "$HELPER_DIR/scripts/backup.sh" ]; then
    BACKUP_LOG="$REPORT_DIR/helper_backup_run_${STAMP}.txt"
    printf 'y\n' | sh "$HELPER_DIR/scripts/backup.sh" backup > "$BACKUP_LOG" 2>&1
    log "backup_run:$BACKUP_LOG:rc=$?"
    LATEST_BACKUP="$(ls -t /mnt/UDISK/printer_data/backups/k2pro_helper/k2pro_config_system_*.tar.gz 2>/dev/null | head -n 1)"
    if [ -n "$LATEST_BACKUP" ] && [ -f "$LATEST_BACKUP" ]; then
        cp -a "$LATEST_BACKUP" "$REMOTE_DIR/"
        log "config_backup:$REMOTE_DIR/$(basename "$LATEST_BACKUP")"
    else
        log "config_backup:missing"
    fi
else
    log "backup_run:skipped:no helper backup script"
fi

find "$REMOTE_DIR" "$REPORT_DIR" -type f -maxdepth 2 2>/dev/null | while IFS= read -r f; do
    sha256sum "$f"
done > "$SHA_FILE"
log "sha256s:$SHA_FILE"
log "DONE:$ROOT_DIR"

printf '%s\n' "$ROOT_DIR"
