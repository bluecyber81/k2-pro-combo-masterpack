#!/bin/sh
# backup.sh - Backup and restore Klipper configuration for K2 Pro/K2 Series printers
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

BACKUP_DIR=/mnt/UDISK/printer_data/backups/k2pro_helper
PRE_RESTORE_DIR=$BACKUP_DIR/pre_restore

backup_config() {
    printf "Backup Klipper configuration and important system files? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    echo ""
    log_info "Backing up Klipper configuration and system scripts..."
    mkdir -p "$BACKUP_DIR"

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    TMP_DIR=/tmp/k2pro_backup_${TIMESTAMP}_$$
    BACKUP_FILE="$BACKUP_DIR/k2pro_config_system_${TIMESTAMP}.tar.gz"
    mkdir -p "$TMP_DIR/printer_data" "$TMP_DIR/system" "$TMP_DIR/helper" "$TMP_DIR/creality/userdata"

    cp -a /mnt/UDISK/printer_data/config "$TMP_DIR/printer_data/" 2>/dev/null
    cp -a /mnt/UDISK/printer_data/database "$TMP_DIR/printer_data/" 2>/dev/null
    cp -a /mnt/UDISK/creality/userdata/box "$TMP_DIR/creality/userdata/" 2>/dev/null
    [ -f "$SCRIPT_DIR/.installed" ] && cp -a "$SCRIPT_DIR/.installed" "$TMP_DIR/helper/.installed" 2>/dev/null
    for f in /etc/rc.d/S55klipper /etc/rc.d/S56moonraker /etc/rc.d/S80nginx /etc/rc.d/S97webrtc /etc/nginx/nginx.conf /etc/rc.local /etc/init.d/moonraker; do
        [ -e "$f" ] && cp -a "$f" "$TMP_DIR/system/$(echo "$f" | tr '/' '_')"
    done
    df -h > "$TMP_DIR/df_h.txt" 2>/dev/null
    uname -a > "$TMP_DIR/uname.txt" 2>/dev/null

    tar -czf "$BACKUP_FILE" -C "$TMP_DIR" .
    rc=$?
    rm -rf -- "$TMP_DIR"

    if [ $rc -eq 0 ]; then
        log_success "Backup saved to: $BACKUP_FILE"
        SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
        log_info "Backup size: $SIZE"
        ls -t "$BACKUP_DIR"/k2pro_config_system_*.tar.gz 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null
        log_info "Keeping last 7 full backups. Older full backups removed."
    else
        log_error "Backup failed."
    fi
    echo ""
    return $rc
}

restore_config() {
    echo ""
    log_info "Available backups:"
    echo ""

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls "$BACKUP_DIR"/k2pro_config_system_*.tar.gz 2>/dev/null)" ]; then
        log_warn "No full helper backups found in $BACKUP_DIR"
        return 1
    fi

    LIST_FILE=/tmp/k2pro_backup_list_$$
    ls -t "$BACKUP_DIR"/k2pro_config_system_*.tar.gz 2>/dev/null > "$LIST_FILE"

    i=1
    while IFS= read -r f; do
        SIZE=$(du -sh "$f" | cut -f1)
        DATE=$(basename "$f" .tar.gz | sed 's/k2pro_config_system_//' | sed 's/klipper_config_//' | sed 's/_/ /')
        echo "  $i) $DATE  [$SIZE]"
        i=$((i+1))
    done < "$LIST_FILE"

    echo "  0) Cancel"
    echo ""
    printf "  Select backup to restore: "
    read choice

    if [ "$choice" = "0" ] || [ -z "$choice" ]; then
        log_info "Cancelled."
        return 0
    fi

    case "$choice" in
        *[!0-9]*)
            rm -f "$LIST_FILE"
            log_error "Invalid selection."
            return 1
            ;;
    esac

    SELECTED=$(sed -n "${choice}p" "$LIST_FILE")
    rm -f "$LIST_FILE"
    if [ -z "$SELECTED" ] || [ ! -f "$SELECTED" ]; then
        log_error "Invalid selection."
        return 1
    fi

    echo ""
    printf "%b\n" "${YELLOW}WARNING: This restores only /mnt/UDISK/printer_data/config by default.${NC}"
    echo "System files and CFS material DB files inside the backup are for manual recovery."
    printf "Overwrite current config files? [y/n]: "
    read confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled."
        return 0
    fi

    RESTORE_STAMP=$(date +%Y%m%d_%H%M%S)
    PRE_RESTORE_FILE="$PRE_RESTORE_DIR/k2pro_pre_restore_config_${RESTORE_STAMP}.tar.gz"
    mkdir -p "$PRE_RESTORE_DIR"
    if [ -d /mnt/UDISK/printer_data/config ]; then
        if tar -czf "$PRE_RESTORE_FILE" -C /mnt/UDISK/printer_data config; then
            log_info "Current config backed up before restore: $PRE_RESTORE_FILE"
        else
            log_error "Could not create pre-restore backup. Restore aborted."
            return 1
        fi
    fi

    RESTORE_TMP=/tmp/k2pro_restore_${RESTORE_STAMP}_$$
    mkdir -p "$RESTORE_TMP"
    if tar -tzf "$SELECTED" | grep -qE '(^/|(^|/)\.\.(/|$))'; then
        rm -rf -- "$RESTORE_TMP"
        log_error "Backup contains unsafe paths. Restore aborted."
        return 1
    fi
    if ! tar -xzf "$SELECTED" -C "$RESTORE_TMP"; then
        rm -rf -- "$RESTORE_TMP"
        log_error "Could not extract backup. Restore failed."
        return 1
    fi
    if [ -d "$RESTORE_TMP/printer_data/config" ]; then
        if cp -a "$RESTORE_TMP/printer_data/config" /mnt/UDISK/printer_data/; then
            log_success "Config restored successfully."
            rm -rf -- "$RESTORE_TMP"
            restart_klipper force
            restore_rc=$?
        else
            rm -rf -- "$RESTORE_TMP"
            log_error "Could not copy restored config into /mnt/UDISK/printer_data. Restore failed."
            restore_rc=1
        fi
    else
        rm -rf -- "$RESTORE_TMP"
        log_error "Backup does not contain printer_data/config. Restore failed."
        restore_rc=1
    fi
    echo ""
    return $restore_rc
}

case "$1" in
    backup)  backup_config ;;
    restore) restore_config ;;
    *)       echo "Usage: $0 [backup|restore]" ;;
esac
